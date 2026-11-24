# Architecture

This document describes the application, the AWS infrastructure, the delivery pipeline and the
design decisions behind the project.

---

## 1. High-level view

```text
                          ┌──────────────────────────────────────────────┐
                          │                  Developer                   │
                          └───────────────────┬──────────────────────────┘
                                              │ git push
                                              ▼
┌─────────────────────────────── AWS VPC 10.0.0.0/16 ───────────────────────────────┐
│                                                                                    │
│  Public subnet A            Public subnet B          Private subnet A/B            │
│  ┌───────────────┐                                   ┌─────────────────────────┐   │
│  │ Jenkins EC2   │──────assume role / push images────►│ ECR (3 repositories)    │   │
│  │ Ansible +     │                                   └───────────┬─────────────┘   │
│  │ Docker/Trivy  │                                               │ pull            │
│  └───────┬───────┘                                               ▼                 │
│          │ git push to manifests                     ┌─────────────────────────┐    │
│          ▼                                           │ EKS cluster (2 groups)  │    │
│  ┌───────────────┐        watches repo              │ namespace: ivolve       │    │
│  │ Git provider  │◄─────────────── ArgoCD ─────────►│ frontend / auth /      │    │
│  └───────────────┘                                │ roadmap / MySQL STS     │    │
│                                                     └─────────────────────────┘    │
│  NAT Gateway ──► Internet (image pulls, apt, Maven/npm/pip)                        │
└────────────────────────────────────────────────────────────────────────────────────┘
```

Two planes:

* **Control plane (CI):** Jenkins builds, scans and pushes images, then commits the new tag to Git.
* **Data plane (CD):** ArgoCD reconciles the cluster with Git. EKS pulls images from ECR.

---

## 2. Application components

| Component | Image | Runtime | Health endpoint | Persistence |
| --- | --- | --- | --- | --- |
| `frontend` | `frontend` | Node 20, Express, EJS | `GET /` | none (sessions in memory) |
| `auth-service` | `auth-service` | Python 3.12, Flask, Gunicorn/Flask dev server | `GET /health` (checks MySQL) | MySQL |
| `roadmap-service` | `roadmap-service` | Java 21, Spring Boot 3.5 | `GET /api/roadmap` | none |
| `mysql` | `mysql:8.0` | MySQL | `mysqladmin ping` | PVC (5 GiB prod, 1 GiB lab) |

Request flow:

1. The browser hits the Ingress, which routes everything to `frontend`.
2. `frontend` renders the login/signup pages and calls `auth-service` (`/api/auth/*`).
3. After login, `frontend` calls `roadmap-service` (`/api/roadmap`) and renders the roadmap.
4. `auth-service` reads/writes the `users` table in `ivolve` and creates it on first use.
5. `frontend` stores the session cookie (secret from the `ivolve-secret` Secret).

Kubernetes objects:

* `Namespace ivolve`
* `ConfigMap ivolve-config` – non-sensitive env (`DB_HOST`, `AUTH_SERVICE_URL`, …)
* `Secret ivolve-secret` – DB credentials and session secret
* `StatefulSet mysql` + headless Service (`mysql-headless`) + ClusterIP Service (`mysql`)
* `Deployment` × 3 + `Service` × 3
* `Ingress ivolve`
* `StorageClass ivolve-sc` (EBS `gp3` in production, `local-path` in the lab)

---

## 3. Network design

| Resource | Configuration |
| --- | --- |
| VPC | `10.0.0.0/16`, DNS hostnames + support enabled |
| Public subnets | `10.0.1.0/24` (AZ a), `10.0.2.0/24` (AZ b), `map_public_ip_on_launch` |
| Private subnets | `10.0.11.0/24` (AZ a), `10.0.12.0/24` (AZ b) |
| Internet Gateway | attached to the public route table |
| NAT Gateway | single EIP, used by both private subnets |
| Route tables | public → IGW, private → NAT |
| NACLs | public allows 80/443/22 + ephemeral; private allows VPC-internal + ephemeral egress |
| Subnet tags | `kubernetes.io/role/elb=1` (public), `kubernetes.io/role/internal-elb=1` (private) |

Security groups:

* Jenkins SG: inbound 22, 80, 8080 (CIDRs are variables; restrict them in production), all outbound.
* EKS control plane and nodes: managed by the EKS module.

---

## 4. Terraform modules

```text
terraform/
├── modules/network   → vpc_id, public/private subnet ids and AZs
├── modules/ecr       → repository URLs (frontend, auth-service, roadmap-service)
├── modules/server    → Jenkins EC2 public IP, instance id, key pair, IAM profile
├── modules/eks       → cluster name/endpoint, node group names
├── backend/          → S3 bucket (versioned, encrypted, public access blocked)
└── environments/
    ├── local         → Floci provider + S3 backend on localhost:4566
    └── prod          → real AWS provider + S3 backend
```

Key decisions:

* **Remote state in S3** with `use_lockfile = true`; no DynamoDB table to manage.
* **`backend/` is a separate root module** so the state bucket exists before the environment is
  initialised (chicken-and-egg bootstrap). It supports `use_local_endpoint` for Floci.
* **Two managed node groups**, one per private subnet/AZ, so the cluster spans two AZs. The
  requirement of two worker nodes is therefore met both by count (1 + 1) and by topology.
* **Ubuntu 24.04 AMI** is discovered with `data.aws_ami` in production; the local environment pins
  Floci's `ami-ubuntu2404-amd64` alias (the `ami-ubuntu2404` alias is arm64 and cannot run on `t3`).
* **No Terraform-managed Kubernetes provider**: cluster bootstrap (ArgoCD, ingress) is kept out of
  the cluster lifecycle to avoid state coupling. ArgoCD installs its own CRDs.

Outputs consumed by the pipeline and runbooks: `ecr_repository_urls`, `jenkins_public_ip`,
`eks_cluster_name`, `eks_cluster_endpoint`, subnet/VPC ids, node group names.

---

## 5. Jenkins design

### Controller

* EC2 `t3.medium`, Ubuntu 24.04, 50 GiB gp3 root volume.
* Provisioned by Ansible (`common → java → docker → jenkins → trivy`).
* Jenkins listens on `8080`; the SG also exposes 80 for a future reverse proxy.
* IAM instance profile with `AmazonEC2ContainerRegistryPowerUser` → no static AWS keys on the box.

### Shared library (`ivolve-shared-library`)

| Step | Purpose |
| --- | --- |
| `buildImage(image, context, dockerfile, buildArgs)` | `docker build` with OCI labels |
| `trivyScan(image, severity, exitOnFindings)` | writes `reports/trivy-<svc>.txt`, fails on findings |
| `ecrLogin(region, useInstanceProfile)` | returns the registry host, `docker login` |
| `pushImage(image)` | `docker push` |
| `cleanupImage(image, prune)` | `docker rmi -f` + 24h prune |
| `updateManifests(name, image, tag, overlay)` | rewrites the Kustomize image block and commits/pushes |

### Pipelines

`frontend`, `auth-service`, `roadmap-service` use the same stage graph:
checkout → build → scan → login → push → cleanup → update manifests.

Parameters: `IMAGE_TAG`, `AWS_REGION`, `SCAN_SEVERITY`, `SKIP_SCAN`, `UPDATE_MANIFESTS`.
Artifacts are archived even when the scan fails; workspaces are cleaned in `post`.

Promotion is **tag-based**: `BUILD_NUMBER-GIT_SHA` (or an explicit `IMAGE_TAG`). The pipeline only
edits `k8s/overlays/prod/kustomization.yaml` and pushes; ArgoCD applies it.

---

## 6. GitOps with ArgoCD

* `argocd/project.yaml` – `AppProject ivolve`, restricts destinations to `ivolve`/`argocd` and
  allows only namespaces + storage classes at cluster scope.
* `argocd/application.yaml` – production app, repo `main`, path `k8s/overlays/prod`,
  automated sync (`prune`, `selfHeal`, retry/backoff).
* `argocd/application-local.yaml` – same app against the local Gitea repository and the
  `k8s/overlays/local` overlay.
* `argocd/install/values-local.yaml` – Helm values for a single-node lab (ClusterIP, insecure HTTP,
  reduced requests).

Sync order is handled by Kubernetes itself (StatefulSet + PVC before dependent pods); probes absorb
startup ordering. `CreateNamespace=true` is harmless because the namespace is also in the overlay.

---

## 7. Local emulation with Floci

| AWS service | Floci behaviour |
| --- | --- |
| S3 | Real bucket API on `:4566`, path-style; used for Terraform state |
| IAM/STS | Accepts any credentials, returns pseudo account `000000000000` |
| EC2 | Real Docker containers; SSH port published on `127.0.0.1:2200+` |
| ECR | Real registry (`localhost:5100`), repository URLs include `localhost` |
| EKS | Real k3s cluster (`localhost:6500`), kubeconfig via `aws eks update-kubeconfig` |

Consequences handled in the code:

* `environments/local` sets every endpoint explicitly and disables credential/account validation.
* Storage class is switched to `rancher.io/local-path` in the local overlay.
* Ingress class is switched to Traefik (bundled with k3s) in the local overlay.
* Images are loaded into k3s containerd with `docker save | ctr images import` so the lab does not
  depend on the emulated registry from inside the cluster.
* The `eks` module accepts `cluster_version = null` because Floci chooses its own k3s version.

---

## 8. Security considerations

* Jenkins: IAM instance profile, no long-lived keys, SSH key pair injected from `platform/keys`
  (git-ignored), SG CIDRs configurable.
* State: S3 versioning, SSE, public access block, native lockfile.
* ECR: scan on push, lifecycle policy (keep the newest 30 images), `force_delete` only in the lab.
* Kubernetes: namespace isolation, secrets mounted as env vars, resource limits, probes, no
  `hostNetwork`, images pinned by tag (digests would be the next step).
* Production hardening backlog: private Jenkins (SSM instead of public SSH), KMS for secrets,
  IRSA for EBS CSI/ALB controller, network policies, Pod Security Admission, image signing (cosign).

---

## 9. Known limitations

* **Floci** simplifies IAM and does not run a real EKS control plane; the "two node groups" exist
  as metadata while k3s schedules everything on one node.
* Workstations with less than 12 GB RAM should run the CI stack and the full cluster in separate
  sessions; `docs/local-lab.md` explains which subsets to run.
* The local k3s lab reached `frontend`, `roadmap-service` and MySQL `Ready`, and `auth-service`
  `Running`; the `auth → mysql` connection can be unreliable on memory-constrained hosts
  (CoreDNS/kube-proxy restarts), so the Compose stack remains the reference end-to-end demo.
* No TLS/DNS automation is included (cert-manager annotations are prepared but commented out).
