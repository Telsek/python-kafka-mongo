# The Leaky Pipeline - Python, Kafka & MongoDB on EKS

A small shop (Harry Potter sweets + LOTR artifacts with DevOps jokes) used to show the full DevOps lifecycle: build, test, release, deploy, scale, break, monitor and tear down - all from git.

You buy something -> the **client** sends it to **Kafka** -> the **api** reads Kafka and saves it in **MongoDB** -> the page shows everything bought. If the api or the database is down, the order waits safely in Kafka and is saved once they're back.

Live (when the cluster is up): <https://shop.mansuraforecast.online>

## Index

- [How it works](#how-it-works)
- [The story in screenshots](#the-story-in-screenshots)
- [Running it](#running-it)
- [CI/CD](#cicd)
- [Tools and why](#tools-and-why)
- [Issues and fixes](#issues-and-fixes)
- [Notes](#notes)

## How it works

```mermaid
flowchart LR
    U[Browser] --> ALB[ALB + HTTPS]
    ALB --> C[client]
    C -->|buy| K[(Kafka x3)]
    K --> A[api, 2-6 pods by KEDA]
    A --> M[(MongoDB x3)]
    C -->|list| A
    V[Vault] -.->|Mongo password via VSO| A
    A & C -.->|traces, logs, metrics| S[SigNoz]
```

### AWS infrastructure

```mermaid
flowchart TB
    NET((Internet)) --> ALB
    subgraph VPC["VPC 10.0.0.0/16 - us-east-1"]
        subgraph PUB["Public subnets"]
            ALB[ALB + HTTPS]
            NAT[NAT gateway]
        end
        subgraph A["AZ a - private 10.0.16.0/20"]
            N1["node 1<br/>Kafka · Mongo · Vault"]
        end
        subgraph B["AZ b - private 10.0.32.0/20"]
            N2["node 2<br/>Kafka · Mongo · Vault"]
        end
        subgraph C["AZ c - private 10.0.48.0/20"]
            N3["node 3<br/>Kafka · Mongo · Vault"]
            N4["node 4<br/>SigNoz, apps, operators"]
        end
    end
    ALB --> N1 & N2 & N3 & N4
    N1 & N2 & N3 & N4 -.->|outbound only| NAT --> NET
```

| | |
| --- | --- |
| VPC | 3 AZs. Public subnets (10.0.1-3.0/24) hold only the ALB and the NAT. Nodes and pods live in private subnets (/20 each - every pod gets a VPC IP) |
| NAT | One for all AZs - saves cost. Tradeoff: if its AZ goes down, nodes lose outbound internet (the shop keeps working) |
| Nodes | 4 x m7i-flex.large (2 vCPU / 8 GB) - the largest type on the AWS free plan. 32 GB total, ~24 GB used |
| Spread | Kafka, Mongo and Vault each run 3 copies, one per AZ. Losing an AZ still leaves 2 of 3 - a majority, so they keep working |
| EKS API | Public, but only reachable from my IP |

Node sizing (memory reserved, estimate):

| Node | Main pods | ~GB of 8 |
| --- | --- | --- |
| 1 | Kafka broker (2), Mongo (1), Vault, small pods | 5.4 |
| 2 | Kafka broker (2), Mongo (1), Vault, small pods | 6.1 |
| 3 | Kafka broker (2), Mongo (1), Vault, small pods | 6.4 |
| 4 | SigNoz + ClickHouse (~3), ArgoCD, operators, shop | 6.6 |

The exact pod placement is decided by Kubernetes at each build; the rule is one Kafka / Mongo / Vault per AZ.

### Repos

Two repos:

| Repo | Holds |
| --- | --- |
| `python-kafka-mongo` (this one) | App code, Dockerfiles, tests, CI/CD workflows, Terraform, load + chaos tests |
| `python-kafka-mongo-gitops` | What runs in the cluster: ArgoCD apps, Kafka/Mongo/Vault manifests, the shop Helm chart |

Terraform builds AWS (VPC, EKS, load balancer controller, DNS, KMS) and installs ArgoCD. ArgoCD then deploys everything else from the GitOps repo.

## The story in screenshots

### 1. It started on a laptop

The first version ran with docker compose. The api was stopped, a buy was made, and it waited in Kafka until the api came back.

| | |
| --- | --- |
| Shop | ![local shop](docs/images/01-local-shop.png) |
| api down, buy still accepted | ![api down](docs/images/02-local-api-down.png) |
| api back, logs show the save | ![logs](docs/images/03-local-logs.png) |
| The buy is in the list | ![after restart](docs/images/04-local-after-restart.png) |

### 2. One command builds AWS

`terraform apply` creates 86 resources. ArgoCD comes up and deploys all 15 apps from git - nothing installed by hand.

| | |
| --- | --- |
| Terraform apply | ![apply](docs/images/05-terraform-apply.png) |
| ArgoCD: 15 apps, all healthy | ![argocd apps](docs/images/06-argocd-apps.png) |

### 3. What got deployed

| | |
| --- | --- |
| The shop: deployed by the release bot, KEDA scaler, Ingress, Vault secret | ![shop tree](docs/images/07-argocd-shop-tree.png) |
| Kafka: 2 small files -> Strimzi builds 3 brokers, 3 disks, the topic (+29 more objects) | ![kafka tree](docs/images/08-argocd-kafka-tree.png) |
| Kafka network: clients connect to one address, 3 brokers behind it | ![kafka network](docs/images/09-argocd-kafka-network.png) |
| The Kafka app's 4 pods (3 brokers + topic operator) spread one per node. Each node shows kernel 6.18 (pinned, see Notes) | ![nodes](docs/images/10-nodes-kernel.png) |
| Vault: 3 pods, 3 disks, active + standby | ![vault](docs/images/11-argocd-vault.png) |

### 4. It's live

| | |
| --- | --- |
| Shop on EKS | ![eks shop](docs/images/12-eks-shop.png) |
| Pods + load balancer address | ![pods ingress](docs/images/13-eks-pods-ingress.png) |

### 5. Shipping a change

Every pull request must pass 6 checks. Merging a release builds the images, pushes them to GHCR and writes the new version into the GitOps repo - ArgoCD deploys it.

| | |
| --- | --- |
| 6 required checks | ![ci](docs/images/14-ci-checks.png) |
| Release: version -> images -> GitOps | ![release](docs/images/15-release-run.png) |

### 6. Breaking it on purpose

k6 sends ~170 buys per second for 3 minutes. Chaos Mesh kills a Kafka broker and slows the api down by 100 ms.

| | |
| --- | --- |
| A broker was killed and came back | ![broker killed](docs/images/16-broker-killed.png) |
| Orders pile up in Kafka -> KEDA scales the api 2 -> 6 | ![keda](docs/images/17-keda-scaled.png) |
| 31,355 buys, 0 failed | ![k6](docs/images/18-k6-chaos.png) |

### 7. A real outage

After a rebuild, one MongoDB member couldn't start (not enough CPU reserved on any node). The api lost its database for about 10 minutes. 4 buys were made during that time.

| | |
| --- | --- |
| SigNoz home: logs, traces and metrics all active. Services table (bottom right): api error rate 9.57% - the failed "list" calls while Mongo was down | ![signoz](docs/images/19-signoz-home.png) |
| Mongo fixed - all 4 buys were saved, none lost | ![buys survived](docs/images/20-buys-survived-mongo.png) |
| SigNoz trace of one buy: client sent it at 13:25:11, api saved it ~10 minutes later (top: 9.95 mins). It waited in Kafka the whole time | ![trace](docs/images/21-signoz-trace.png) |

### 8. Tearing it down

`destroy.sh` removes what Kubernetes created (load balancer, disks), then runs `terraform destroy`. Nothing is left behind.

| | |
| --- | --- |
| 86 destroyed | ![destroy](docs/images/22-destroy.png) |
| AWS check: no VPC, cluster, nodes, disks or load balancers | ![clean](docs/images/23-aws-clean.png) |

## Running it

Needs `terraform/terraform.tfvars` with `admin_cidrs = ["<your IP>/32"]`):

```bash
cd terraform
terraform init
terraform apply -auto-approve   # ~10 min, ArgoCD needs ~5 more
./destroy.sh                    # ~15 min
```

Why a destroy script and not just `terraform destroy`: the load balancer, DNS record and disks are created by Kubernetes controllers, not by Terraform. Terraform doesn't know they exist, and they block the VPC from being deleted. The script deletes the apps first, waits until AWS has removed those, then runs `terraform destroy`.

Load + chaos test (cluster up):

```bash
kubectl apply -f chaos/chaos-test.yaml
docker run --rm -i grafana/k6:2.1.0 run - < tests/load/buy.js
```

## CI/CD

Both pipelines run on **GitHub Actions** (`.github/workflows/`). GitHub Flow: every change goes through a pull request to `main`, which is protected. Commit messages follow Conventional Commits (`feat:`, `fix:`), which decide the next version.

**CI** - `ci.yml`, GitHub Actions, on every pull request. All 6 must pass to merge:

| Check | What |
| --- | --- |
| gitleaks | No secrets in the code or history |
| tests | pytest with real Kafka + Mongo in throwaway containers (Testcontainers) |
| codeql | Code security scan |
| images (api), images (client) | Build each image and scan it with Trivy |
| terraform-scan | Trivy scan of the Terraform |

**CD** - two halves:

| Half | Tool | What |
| --- | --- | --- |
| Delivery | GitHub Actions (`release.yml`, on every merge to `main`) | release-please opens a release PR (version + changelog). Merging it builds the images, pushes them to GHCR with the version tag, and writes the version into the GitOps repo |
| Deployment | ArgoCD (in the cluster) | Sees the new version in the GitOps repo and deploys it |

GitHub Actions never touches the cluster - it only writes to git, and ArgoCD pulls from git (pull model). So no cluster credentials live in GitHub.

## Tools and why

| Area | Tool | Why |
| --- | --- | --- |
| Infra | Terraform | Whole AWS setup in code, one command up and down |
| Platform | EKS (4 nodes, 3 AZs) | Kafka and Mongo clusters next to the apps, self-healing, scaling. Losing one AZ still leaves a majority |
| Deploy | ArgoCD (app of apps) | Git is the truth; the cluster matches it |
| Kafka | Strimzi | Runs a 3-broker Kafka from 2 small files |
| Database | MongoDB operator | 3-member replica set |
| Secrets | Vault + Vault Secrets Operator | Passwords generated by Vault, never in git. Vault unlocks itself with AWS KMS |
| Load balancer | AWS LB Controller + ExternalDNS | Ingress -> ALB with HTTPS, DNS record made automatically |
| Scaling | KEDA | Scales the api on Kafka backlog, not CPU |
| Monitoring | OpenTelemetry + SigNoz | Logs, metrics and traces in one place |
| Tests | pytest + Testcontainers, k6, Chaos Mesh | Real dependencies in tests, load, and failure testing |
| Security | Gitleaks, CodeQL, Trivy | Secrets, code and image/infra scanning |
| CI/CD | GitHub Actions | CI on every pull request, release on every merge |
| Release | release-please, GHCR | Versions and changelog from commit messages |

## Issues and fixes

The main ones (symptom -> cause -> fix):

- **MongoDB member stuck Pending** -> its helper container reserved 500m CPU by default and no node had room -> lowered it to 100m. The operator waited for all members before applying the change, so the stuck pod was patched and recreated once.
- **Destroy hung on SigNoz** -> its database (ClickHouse) has a lock that its operator keeps adding back -> the script removes it in a loop until SigNoz is gone.
- **MongoDB 8.0 crashes on new nodes** -> kernel 6.19+ -> node image pinned.
- **KEDA never scaled under load** -> the api was too fast for a backlog to build -> chaos test slows it down to show scaling.
- **SigNoz collectors wouldn't start** -> no organization existed -> admin user + org created at startup, password from Vault.
- **Trivy failed the images** -> old libraries inside pip itself -> pip removed from the final images.
- **Release PR didn't run CI** -> PRs made by the default GitHub token don't trigger workflows -> a personal token is used.

## Notes

- **Node image pinned** (`ami_release_version` in `eks.tf`): MongoDB 8.0 crashes on kernel 6.19+, and every apply would otherwise take the newest image.
- **Vault TLS is off inside the cluster** - traffic stays inside the private network. In production I'd turn it on.
- **EKS API is public but locked to my IP** (`admin_cidrs`), so kubectl works from my laptop. Trivy flags it; accepted in `.trivyignore` with the reason.
- **ArgoCD is not reachable from the internet** - it checks git every 3 minutes instead of using a webhook.
- **Free plan sizing:** largest allowed node is m7i-flex.large (2 vCPU / 8 GB). 4 nodes, ~24 GB of the 32 GB used.
- **Daily destroy:** the cluster is destroyed every evening and rebuilt from git when needed.
