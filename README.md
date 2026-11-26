# Python, Kafka & MongoDB

Shop app for the Kafka/Mongo task. You buy something, it goes to Kafka, the API server saves it in Mongo, and the page shows everything bought. The shop is Harry Potter sweets and LOTR items with DevOps jokes, just for fun.

Runs locally with docker compose, and on AWS (ECS Fargate) with Terraform.

## Index

- [Python, Kafka \& MongoDB](#python-kafka--mongodb)
  - [Index](#index)
  - [How it works](#how-it-works)
  - [Running it](#running-it)
  - [Testing](#testing)
  - [Screenshots](#screenshots)
  - [Burndown](#burndown)
  - [Notes](#notes)

## How it works

The client server (FastAPI) serves the page, sends buys to Kafka and asks the API server for the list. The API server (FastAPI) reads Kafka in the background, saves to Mongo and returns the list.

```mermaid
flowchart LR
    U[Browser] --> L[ALB / localhost]
    L --> C[Client server]
    C -->|buy| K[(Kafka)]
    K --> A[API server]
    A --> M[(MongoDB)]
    C -->|getAllBoughtItems| A
```

## Running it

Locally:

```bash
docker compose up -d --build
```

Then open <http://localhost:8080>

On AWS:

```bash
cd terraform
terraform init
terraform apply -auto-approve     # ~3 min
terraform destroy -auto-approve
```

Then open <https://shop.mansuraforecast.online>

Terraform builds the VPC, an ALB with HTTPS, the DNS record, ECR (and builds/pushes the images), and the 4 containers on ECS Fargate. Only the ALB is public. The state bucket, DNS zone and cert were made once and aren't part of it.

## Testing

Locally: stopped the API server, bought something, started it again. The buy waited in Kafka and got saved once the API was back (Horn of Gondor).

On AWS: set the api service to 0 tasks, bought 2 items, then set it back to 1. A brand new api container started and saved both straight away (Mithril TLS Vest and Palantír Dashboard in the logs screenshot).

Also did a full destroy + apply, bought an item right after and it showed up straight away. Checked after destroy that nothing was left.

## Screenshots

| What | Screenshot |
| --- | --- |
| Shop | ![shop](docs/images/01-shop.png) |
| API down | ![api down](docs/images/02-api-down.png) |
| API logs after restart | ![api logs](docs/images/03-logs.png) |
| List after restart | ![after restart](docs/images/04-after-restart.png) |
| Shop on AWS | ![aws shop](docs/images/05-aws-shop.png) |
| ECS services | ![ecs services](docs/images/06-ecs-services.png) |
| ECR | ![ecr](docs/images/07-ecr.png) |
| Terraform apply | ![terraform apply](docs/images/08-terraform-apply.png) |
| AWS: API down | ![aws api down](docs/images/09-aws-api-down.png) |
| AWS: API logs after restart | ![aws api logs](docs/images/10-aws-api-logs.png) |
| AWS: list after restart | ![aws after restart](docs/images/11-aws-after-restart.png) |

## Burndown

| # | Task | Status |
| --- | --- | --- |
| 1 | Design + review | done |
| 2 | Compose: Kafka + Mongo | done |
| 3 | API + client servers | done |
| 4 | Frontend + theme | done |
| 5 | Testing | done |
| 6 | Terraform on AWS | done |
| 7 | Destroy/apply test | done |
| 8 | API down test on AWS | done |

## Notes

- Kafka runs without ZooKeeper (KRaft mode), so it's one container instead of two
- Package and image versions are fixed so a rebuild never pulls something new and breaks. Mongo and the Python base image are fixed to the minor version, so they still get patch updates
- On AWS the shop first took ~5 min to work after apply, because the API started before kafka and mongo. Now Terraform starts those two first and waits
- For real production I'd use private subnets + NAT, MSK for Kafka, DocumentDB for Mongo, and build the images in CI
