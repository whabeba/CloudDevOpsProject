# Jenkins CI

Three pipeline jobs (`frontend`, `auth-service`, `roadmap-service`) share one Groovy library:

```text
jenkins/
├── shared-library/vars/     # the steps below
├── pipelines/               # one Jenkinsfile per service
└── README.md
```

---

## 1. Shared library API

Declared at the top of every Jenkinsfile:

```groovy
@Library('ivolve-shared-library') _
```

| Step | Signature | What it does |
| --- | --- | --- |
| `buildImage` | `buildImage(image:, context:, dockerfile:, buildArgs:, extraArgs:)` | `docker build --pull` with OCI labels (`revision`, `source`) |
| `trivyScan` | `trivyScan(image:, name:, severity:, ignoreUnfixed:, exitOnFindings:, withSbom:)` | Trivy image scan; table report in `reports/trivy-<name>.txt`; fails on findings by default |
| `ecrLogin` | `ecrLogin(region:, registry:, useInstanceProfile:, *CredentialsId:)` | `aws ecr get-login-password \| docker login`; **returns the registry host** |
| `pushImage` | `pushImage(image:)` | `docker push` |
| `cleanupImage` | `cleanupImage(image:, prune:)` | `docker rmi -f`, optional 24h `docker image prune` |
| `updateManifests` | `updateManifests(name:, image:, tag:, overlay:, branch:, sshCredentialsId:, gitCredentialsId:, message:)` | rewrites the Kustomize `images:` entry, commits, pushes |

### `updateManifests` details

* Edits only the `newName`/`newTag` pair matching `name` in
  `k8s/overlays/prod/kustomization.yaml` (awk state machine — no `kustomize` binary required).
* Creates no commit when the tag is unchanged (idempotent rebuilds).
* Pushes with `sshagent` when `sshCredentialsId` is supplied, otherwise it uses an HTTPS
  username/password credential (`git-credentials` by default).

---

## 2. Required credentials

| ID | Type | Used by |
| --- | --- | --- |
| `aws-account-id` | Secret text | `ecrLogin` (only when not using the instance profile) |
| `aws-access-key-id` | Secret text | `ecrLogin` |
| `aws-secret-access-key` | Secret text | `ecrLogin` |
| `github-ssh` | SSH username with private key | `updateManifests` (production) |
| `gitea-credentials` | Username with password | local lab only (job + library checkout) |

On EC2 the pipelines run with `USE_INSTANCE_PROFILE=true` (set in each Jenkinsfile) and use the
instance role — no AWS keys are stored in Jenkins.

---

## 3. Pipeline stages

```text
Checkout ─► Build image ─► Scan image ─► Push to ECR ─► Cleanup local ─► Update manifests
                              │ (skippable)
                              └─ HIGH/CRITICAL findings fail the build
```

Parameters:

| Parameter | Default | Meaning |
| --- | --- | --- |
| `IMAGE_TAG` | `BUILD_NUMBER-GIT_SHA[-1:]` | override the tag (e.g. a release version) |
| `AWS_REGION` | `us-east-1` | ECR region |
| `SCAN_SEVERITY` | `HIGH,CRITICAL` | Trivy severities that fail |
| `SKIP_SCAN` | `false` | bypass Trivy (not recommended) |
| `UPDATE_MANIFESTS` | `true` | commit the new tag for ArgoCD |

`post` always archives `reports/**`, prints `docker system df`, and cleans the workspace.

---

## 4. Job setup (production)

1. *Manage Jenkins → System → Global Trusted Pipeline Libraries*: add `ivolve-shared-library`,
   default version `main`, modern SCM → Git.
2. Create three **Pipeline** jobs, each with *Pipeline script from SCM*:
   repository URL, branch `main`, script path `jenkins/pipelines/<service>.Jenkinsfile`.
3. Add the credentials from §2.
4. Build `frontend` once; verify the Trivy report artifact and the manifest commit.

## 5. Local lab (configuration as code)

`platform/jenkins/` builds an image with Jenkins LTS, Docker CLI, AWS CLI v2, kubectl and Trivy, and
applies `casc/jenkins.yaml`, which creates:

* the admin user (`admin` / `$JENKINS_ADMIN_PASSWORD`, default `admin`),
* the three jobs pointed at Gitea,
* the shared library,
* the credential ids listed above,
* the AWS/Floci environment variables.

```bash
docker compose -f platform/docker-compose.yml up -d --build
# http://localhost:8081
```

See [`../docs/local-lab.md`](../docs/local-lab.md) for the Gitea push and ECR routing details.

---

## 6. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `denied: Your Authorization Token has expired` | ECR token is 12 h; the login step runs every build, re-run it manually if needed |
| `Cannot connect to the Docker daemon` | Jenkins user not in `docker` group, or `/var/run/docker.sock` not mounted |
| Trivy DB download fails | allow `ghcr.io`/`aquasec` egress or pre-seed `TRIVY_CACHE_DIR` |
| `git push` fails from `updateManifests` | add `github-ssh` deploy key with write access, or the `git-credentials` HTTPS token |
| Job uses an old library revision | *Manage Jenkins → Global Libraries* → uncheck “Allow default version to be overridden”, or run *Rebuild* |
| Local lab: `localhost:5100` unreachable from Jenkins | ensure `extra_hosts: host-gateway` is present and Floci publishes 5100 |
