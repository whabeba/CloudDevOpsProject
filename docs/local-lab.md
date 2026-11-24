# Local lab (Floci — fully offline)

The entire platform runs on one Windows machine with Docker Desktop:

* **Floci** emulates AWS (`localhost:4566`), including a real k3s-backed EKS cluster, a real ECR
  registry and real EC2 containers.
* **Gitea** plays the role of GitHub for ArgoCD (optional).
* **Jenkins** runs in Docker with the shared library mounted from this repository (optional).

Reference end-to-end demo: the Compose stack (`docker compose up -d --build`). The Kubernetes path
below has been validated on a single workstation; results and limits are recorded at the end.

---

## 1. Prerequisites

| Tool | Notes |
| --- | --- |
| Docker Desktop | Linux containers, ≥ 12 GB RAM allocated (CI + ArgoCD stack; 8 GB is enough for Compose + Floci) |
| Terraform | ≥ 1.10, on `PATH` |
| AWS CLI | v1 or v2, on `PATH` |
| kubectl | on `PATH` |
| OpenSSH | `ssh-keygen` / `ssh` (Windows optional feature) |
| curl / jq | for the optional Gitea/ArgoCD steps |

Windows + pip AWS CLI note: if `aws` fails with *"File association not found for extension .py"*,
run it as `python -m awscli …` (and see the kubeconfig note in §5).

---

## 2. Start Floci

```powershell
docker network create ivolve-lab

docker run -d --name floci --network ivolve-lab `
  -p 4566:4566 `
  -v //var/run/docker.sock:/var/run/docker.sock `
  -e FLOCI_STORAGE_MODE=hybrid `
  floci/floci:latest
```

```powershell
# health: every emulated service should be "running"
(Invoke-WebRequest -UseBasicParsing http://localhost:4566/_floci/health).Content
```

Ports Floci publishes on the host:

| Port | Purpose |
| --- | --- |
| `4566` | AWS API |
| `5100` | ECR registry |
| `6500` | EKS (k3s) API server |
| `2200+` | SSH for each emulated EC2 instance |

> Emulated resources live inside the `floci` container. Recreating the container resets AWS state
> (including the Terraform state bucket), so re-run the Terraform steps afterwards.

---

## 3. SSH key

```powershell
ssh-keygen -t rsa -b 4096 -f platform\keys\id_rsa -N '""'
```

`platform/keys/` is git-ignored. The public key is injected into the emulated EC2 instance.

---

## 4. Terraform (state bucket + infrastructure)

```powershell
$env:AWS_ACCESS_KEY_ID="test"; $env:AWS_SECRET_ACCESS_KEY="test"; $env:AWS_DEFAULT_REGION="us-east-1"

# 4.1 state bucket inside Floci's S3
cd terraform\backend
terraform init
terraform apply -auto-approve -var use_local_endpoint=true -var force_destroy=true

# 4.2 the environment
cd ..\environments\local
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init
terraform apply -auto-approve
```

Result:

```text
Apply complete! Resources: 38 added.
ecr_repository_urls = {
  auth-service    = "000000000000.dkr.ecr.us-east-1.localhost:5100/auth-service"
  frontend        = "000000000000.dkr.ecr.us-east-1.localhost:5100/frontend"
  roadmap-service = "000000000000.dkr.ecr.us-east-1.localhost:5100/roadmap-service"
}
eks_cluster_name     = "ivolve-eks"
eks_cluster_endpoint = "https://localhost:6500"
eks_node_group_names = ["ivolve-eks-ng-1", "ivolve-eks-ng-2"]
jenkins_public_ip    = "127.0.0.1"     # SSH is on 127.0.0.1:2200
```

Gotcha: Floci's `ami-ubuntu2404` alias is **arm64** and cannot run on `t3.medium`. The local
environment pins `ami-ubuntu2404-amd64` (already the default).

SSH check:

```powershell
ssh -i platform\keys\id_rsa -p 2200 -o StrictHostKeyChecking=no root@127.0.0.1
# Ubuntu 24.04.5 LTS
```

---

## 5. Kubernetes

```powershell
aws eks update-kubeconfig --name ivolve-eks --kubeconfig platform\kubeconfig-floci.yaml
kubectl --kubeconfig platform\kubeconfig-floci.yaml get nodes
```

If `aws` is the pip wrapper, edit the generated kubeconfig `users[0].user.exec` block:

```yaml
command: python
args:
  - -m
  - awscli
  - eks
  - get-token
  - --cluster-name
  - ivolve-eks
  - --region
  - us-east-1
  - --output
  - json
```

Expected:

```text
NAME           STATUS   ROLES           VERSION
e03b5c92d750   Ready    control-plane   v1.34.1+k3s1
```

### 5.1 Build the images

```powershell
docker compose build          # creates ivolve-frontend, ivolve-auth-service, ivolve-roadmap-service

$reg = "000000000000.dkr.ecr.us-east-1.localhost:5100"
docker tag ivolve-frontend:latest       "$reg/frontend:latest"
docker tag ivolve-auth-service:latest   "$reg/auth-service:latest"
docker tag ivolve-roadmap-service:latest "$reg/roadmap-service:latest"
```

### 5.2 Load them into the emulated cluster

The k3s node runs in the `floci-eks-ivolve-eks` container, so load images straight into containerd
(no registry pull needed):

```powershell
foreach ($img in @("$reg/frontend:latest", "$reg/auth-service:latest", "$reg/roadmap-service:latest", "mysql:8.0")) {
  cmd /c "docker save $img | docker exec -i floci-eks-ivolve-eks ctr -n k8s.io images import -"
}
```

`cmd /c` is required on Windows: a PowerShell pipeline would corrupt the binary stream.

### 5.3 Deploy the local overlay

```powershell
kubectl --kubeconfig platform\kubeconfig-floci.yaml apply -k k8s/overlays/local
kubectl --kubeconfig platform\kubeconfig-floci.yaml -n ivolve get pods,pvc,svc,ingress
```

The local overlay:

* uses 1 replica per component (single k3s node),
* switches the StorageClass to `rancher.io/local-path`,
* switches the Ingress class to Traefik,
* shrinks the MySQL volume to 1 GiB,
* points images at the emulated ECR (`…localhost:5100`).

### 5.4 Open the app

```powershell
kubectl --kubeconfig platform\kubeconfig-floci.yaml -n ivolve port-forward svc/frontend 3000:3000
```

Then browse <http://localhost:3000>. For the ingress hostname, add
`127.0.0.1 ivolve.local` to `C:\Windows\System32\drivers\etc\hosts` and use
`kubectl -n traefik port-forward ...` (or keep the port-forward above).

---

## 6. Optional: Jenkins + Gitea (CI in the lab)

The full CI and GitOps stack (Floci + k3s + Jenkins + Gitea + ArgoCD + the application) needs at
least 12 GB of RAM. On smaller workstations run the CI stack **or** the full ArgoCD/k3s stack in
separate sessions.

```powershell
docker compose -f platform/docker-compose.yml up -d --build
```

Services:

| URL | Credentials |
| --- | --- |
| <http://localhost:8081> | `admin` / `JENKINS_ADMIN_PASSWORD` (default `admin`) |
| <http://localhost:3001> | Gitea admin (create in §6.1) |

Jenkins is fully configured by JCasC (`platform/jenkins/casc/jenkins.yaml`):
admin user, the three pipeline jobs, the shared library and the credential ids
(`gitea-credentials`, `aws-account-id`, `aws-access-key-id`, `aws-secret-access-key`).

### 6.1 Create the local Git remote

```powershell
$pw = "ivolve-lab-pass"
docker exec ivolve-gitea gitea admin user create --admin `
  --username ivolve --password $pw --email ivolve@local --must-change-password=false

# create an empty repository "ivolve/CloudDevOpsProject" in the UI, then:
git remote add local http://ivolve:$pw@localhost:3001/ivolve/CloudDevOpsProject.git
git push local main
```

Jenkins clones `http://gitea:3000/ivolve/CloudDevOpsProject.git` over the Compose network, so the
jobs work without exposing Gitea.

> Pushing to **Gitea** is local only. Nothing is sent to GitHub.

### 6.2 ECR login inside Jenkins

Floci advertises `000000000000.dkr.ecr.us-east-1.localhost:5100`. The Compose file maps that
hostname to the Docker host (`extra_hosts: host-gateway`), so `docker login/push` from the Jenkins
container reaches the emulated registry on host port 5100.

`AWS_ENDPOINT_URL=http://floci:4566` is set globally in JCasC; the Jenkins image installs AWS CLI v2,
which honours that variable.

---

## 7. Optional: ArgoCD (GitOps in the lab)

```powershell
# install (internet required)
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace `
  -f argocd/install/values-local.yaml

kubectl -n argocd rollout status deploy/argocd-server

# project + local application (Gitea on the Docker host)
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/application-local.yaml

# UI
kubectl -n argocd port-forward svc/argocd-server 8082:80
# password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | %{[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))}
```

ArgoCD clones `http://172.17.0.1:3001/ivolve/CloudDevOpsProject.git` (Gitea on the host) and syncs
`k8s/overlays/local`. Use the ArgoCD UI to trigger **Sync** and watch the `ivolve` namespace.

If Gitea is private, add the repository credentials in
*Settings → Repositories → Connect repo* (username/password) before creating the Application.

---

## 8. Validation & known limitations

Validated on a single workstation:

| Check | Result |
| --- | --- |
| `docker compose up` stack | ✅ signup → login → roadmap, `/health` = `UP` |
| `terraform validate` (all roots/modules) | ✅ |
| Terraform apply against Floci | ✅ 38 resources: VPC/subnets/NAT/NACLs, ECR ×3, IAM, Jenkins EC2, EKS + 2 node groups |
| SSH into emulated EC2 | ✅ Ubuntu 24.04.5, port 2200 |
| k3s cluster reachable | ✅ 1 control-plane node `Ready` |
| `kubectl apply -k k8s/overlays/local` | ✅ 14 objects, PVC bound with `local-path` |
| Pods | ✅ `frontend`, `roadmap-service`, `mysql` Ready; `auth-service` Running |
| `auth-service` readiness in the lab | ⚠️ intermittently 503: `auth → mysql` service routing can be unreliable on memory-constrained emulators (CoreDNS/kube-proxy restarts) |
| Ansible | ✅ playbook and roles validated; run against a host with internet access |
| Jenkins/ArgoCD lab | ✅ configuration and manifests provided; run on a workstation with ≥ 12 GB RAM for the full stack |

Mitigations already in the repo:

* `startupProbe` added to all three deployments so slow JVM / DB warm-up never triggers liveness kills.
* Resource requests/limits tuned for a single small node in the local overlay.
* The Compose stack remains the canonical end-to-end functional demo.

---

## 9. Cleanup

```powershell
kubectl delete -k k8s/overlays/local
docker compose -f platform/docker-compose.yml down

cd terraform/environments/local
terraform destroy -auto-approve

cd ..\..\backend
terraform destroy -auto-approve -var use_local_endpoint=true -var force_destroy=true

docker rm -f floci
docker network rm ivolve-lab
```
