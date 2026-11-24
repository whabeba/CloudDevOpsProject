# Production setup (real AWS)

Runbook for deploying the project to a real AWS account. For the offline emulator, see
[`local-lab.md`](local-lab.md).

---

## 0. Prerequisites

| Tool | Version | Notes |
| --- | --- | --- |
| Terraform | ≥ 1.10 | `use_lockfile` native S3 locking |
| AWS CLI | v2 | `aws sts get-caller-identity` must work |
| kubectl | ≥ 1.29 | |
| Helm | ≥ 3.14 | ArgoCD + ingress-nginx |
| Ansible | ≥ 2.16 | `ansible-galaxy` for collections |
| Git | any | |
| Docker | any | only for building images locally; Jenkins builds in CI |

```bash
aws configure                 # or export AWS_PROFILE
export AWS_REGION=us-east-1
ssh-keygen -t rsa -b 4096 -f platform/keys/id_rsa -N ""
```

`platform/keys/` is git-ignored; never commit the private key.

---

## 1. Bootstrap the Terraform state bucket

The bucket must exist before `environments/prod` can initialise its S3 backend.

```bash
cd terraform/backend

terraform init
terraform apply \
  -var 'bucket_name=ivolve-terraform-state-<unique-suffix>' \
  -var 'aws_region=us-east-1' \
  -var 'use_local_endpoint=false'
```

Then point the production environment at it:

```hcl
# terraform/environments/prod/backend.tf
bucket = "ivolve-terraform-state-<unique-suffix>"
key    = "prod/terraform.tfstate"
region = "us-east-1"
```

The bucket is versioned, SSE-encrypted, and has all public access blocked.

---

## 2. Provision the infrastructure

```bash
cd terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars
```

Edit at minimum:

```hcl
project_name        = "ivolve"
aws_region          = "us-east-1"
ssh_public_key_path = "../../../platform/keys/id_rsa.pub"
ssh_cidr_blocks     = ["<your-ip>/32"]      # do not leave 0.0.0.0/0
jenkins_cidr_blocks = ["<your-ip>/32"]
cluster_version     = "1.31"
```

```bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Takes ~15–20 minutes (EKS is the slow part). Outputs:

```bash
terraform output
# ecr_repository_urls = { auth-service = "...", frontend = "...", roadmap-service = "..." }
# eks_cluster_name    = "ivolve-eks"
# jenkins_public_ip   = "x.x.x.x"
```

---

## 3. Cluster add-ons

```bash
aws eks update-kubeconfig --region us-east-1 --name ivolve-eks
kubectl get nodes          # 2 worker nodes, one per private subnet/AZ
```

### EBS CSI driver (required by `k8s/base/storageclass.yaml`)

```bash
# Allow the node role to manage EBS volumes, then install the managed add-on.
aws iam attach-role-policy \
  --role-name ivolve-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

aws eks create-addon \
  --cluster-name ivolve-eks \
  --addon-name aws-ebs-csi-driver \
  --resolve-conflicts OVERWRITE
```

### ingress-nginx

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer
kubectl -n ingress-nginx get svc ingress-nginx-controller   # wait for EXTERNAL-IP
```

Point `ivolve.example.com` (or your domain) at that load balancer, and adjust
`k8s/overlays/prod/patch-ingress.yaml`.

---

## 4. Configure the Jenkins server with Ansible

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-inventory --graph            # discovers tag:Name=ivolve-jenkins
ansible-playbook playbook.yml
```

The playbook installs Java 21, Docker, Jenkins and Trivy, then prints the initial admin password
(read from `/var/lib/jenkins/secrets/initialAdminPassword`).

Open `http://<jenkins_public_ip>:8080`, finish the wizard, and create:

| Credential id | Type | Value |
| --- | --- | --- |
| `aws-account-id` | Secret text | 12-digit account id |
| `aws-access-key-id` | Secret text | IAM key (alternative to the instance profile) |
| `aws-secret-access-key` | Secret text | IAM secret |
| `github-ssh` | SSH username with private key | deploy key allowed to push to the manifests repo |

> The pipelines use `USE_INSTANCE_PROFILE=true` by default, so the EC2 role is used and the three
> AWS credentials are only needed if you move Jenkins off EC2.

### Shared library

**Manage Jenkins → System → Global Trusted Pipeline Libraries → Add**

* Name: `ivolve-shared-library`
* Default version: `main`
* Retrieval: modern SCM → Git → repository URL, credentials as needed

### Jobs

Create three **Pipeline** jobs (`frontend`, `auth-service`, `roadmap-service`) with:

* Definition: *Pipeline script from SCM*
* SCM: your repository, branch `main`
* Script path: `jenkins/pipelines/<service>.Jenkinsfile`

Build once per service. Each build ends with a commit that bumps the image tag in
`k8s/overlays/prod/kustomization.yaml`.

---

## 5. Install ArgoCD and the application

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace

# Expose the UI (or put it behind the same ingress)
kubectl -n argocd port-forward svc/argocd-server 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

Before applying the GitOps resources:

1. Replace `000000000000` in `k8s/overlays/prod/kustomization.yaml` with your account id.
2. Replace the `repoURL` in `argocd/application.yaml` with your repository.
3. (Optional) Update `sourceRepos` in `argocd/project.yaml` to the same URL only.

```bash
kubectl apply -k argocd
kubectl -n argocd get applications
kubectl -n ivolve get pods,svc,ingress,pvc
```

ArgoCD syncs `k8s/overlays/prod` automatically; `selfHeal` reverts manual drift and `prune` removes
deleted objects.

---

## 6. Verify the deployment

```bash
kubectl -n ivolve rollout status deploy/frontend
kubectl -n ivolve rollout status deploy/auth-service
kubectl -n ivolve rollout status deploy/roadmap-service
kubectl -n ivolve get pods -o wide
```

Then open `http://ivolve.example.com` (or the ingress LB address with a `Host` header), sign up,
log in, and confirm the roadmap page. `GET /health` on `auth-service` must report the DB as
connected.

Rollback:

```bash
kubectl -n argocd patch application ivolve --type merge \
  -p '{"operation":{"sync":{"revision":"<previous-sha>"}}}'
# or revert the manifest commit in Git — ArgoCD self-heals
```

---

## 7. Teardown

```bash
# Remove workloads first so the ELB/PVCs are cleaned up.
kubectl delete -k argocd
kubectl delete -k k8s/overlays/prod

helm uninstall ingress-nginx -n ingress-nginx
helm uninstall argocd -n argocd

cd terraform/environments/prod
terraform destroy

# State bucket (only when you are done for good)
cd ../../backend
terraform destroy -var 'bucket_name=ivolve-terraform-state-<unique-suffix>' -var 'use_local_endpoint=false'
```

EKS and NAT gateways are the main cost drivers; destroy them when not in use.
