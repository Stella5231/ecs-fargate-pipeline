# ECS Fargate CI/CD Pipeline

[![deploy](https://github.com/Lokesh9000/ecs-fargate-pipeline/actions/workflows/deploy.yml/badge.svg)](https://github.com/Lokesh9000/ecs-fargate-pipeline/actions/workflows/deploy.yml)

Small project to learn AWS + Terraform + Docker + CI/CD by actually building
and running something, instead of just reading about it.

**Current status: torn down.** All the evidence in `docs/incidents/` is
from a real deployed run of this - nothing was simulated - but between
work sessions the environment is destroyed to avoid ongoing cost. Bring
it back with `terraform apply` in `terraform/environments/dev` (see the
"terraform" section below); everything through incident 5 comes back
identically, that part's been proven.

## what this is

A tiny Flask API, containerized, deployed on ECS Fargate behind an ALB,
provisioned entirely with Terraform, deployed through GitHub Actions.

Endpoints:
- `GET /` - basic info, returns the container hostname (useful for seeing
  requests spread across tasks)
- `GET /health` - used by both the ALB and the ECS container health check
- `GET /crash` - marks the app unhealthy on purpose (see
  [docs/incidents/01-crash-self-heal.md](docs/incidents/01-crash-self-heal.md)
  for why this isn't just `os._exit()`), to watch ECS detect it and
  replace the task
- `GET /burn?seconds=N` - burns CPU for N seconds (max 30), to push
  the service's CPU over the autoscaling target

## status

- [x] app + tests running locally
- [x] Dockerfile
- [x] Terraform: networking (VPC, public subnets, IGW, route table)
- [x] Terraform: ECR (immutable tags, image scanning, lifecycle policy,
  `force_delete` so `terraform destroy` actually works - see
  [docs/incidents/05-destroy-recreate.md](docs/incidents/05-destroy-recreate.md))
- [x] Terraform: ECS + ALB (Fargate service, target group health check on /health)
- [x] image built and pushed to ECR, service verified live and healthy through the ALB
- [x] GitHub OIDC role for CI/CD (no stored AWS keys)
- [x] GitHub Actions pipeline (test -> build -> push -> deploy)
- [x] CloudWatch alarms (5xx count, unhealthy targets, ECS high CPU -> SNS -> email)
- [x] ECS deployment circuit breaker (auto-rollback on failed deploys)
- [x] ECS service autoscaling (CPU target tracking, 1-3 tasks)
- [x] failure scenario writeups, run against the live environment - see
  [docs/incidents/](docs/incidents/)
- [x] destroy -> recreate proven end to end

## incidents

Ran these against the actual live environment, not simulated - real
timestamps, real `aws` CLI output, in [docs/incidents/](docs/incidents/):

1. [crash -> ECS self-heals](docs/incidents/01-crash-self-heal.md) - three
   failed attempts at killing the container from inside itself, why they
   failed, and the health-check-based approach that actually works
2. [security misconfiguration + drift detection](docs/incidents/02-security-drift.md) -
   manually opened the task security group to the internet, `terraform
   plan` caught it as drift, `terraform apply` fixed it
3. [load test -> autoscaling](docs/incidents/03-load-autoscale.md) -
   sustained load, a scale-out from 1 to 2 tasks in under a minute once
   the CloudWatch alarm actually breached, an unplanned health-check
   starvation finding along the way, and confirmed scale-in back down
4. [bad deploy -> automatic rollback](docs/incidents/04-bad-deploy-rollback.md) -
   deployed a genuinely broken image, watched the ECS circuit breaker
   retry 3 times over ~14 minutes then roll back automatically with zero
   downtime, then found (and fixed) the part that *isn't* automatic:
   reconciling Terraform's state afterward so it doesn't redeploy the
   broken image again on the next unrelated `apply`
5. [destroy -> recreate](docs/incidents/05-destroy-recreate.md) - proved
   the environment doesn't depend on anything manual; also ran into (and
   documented, and fixed) `terraform destroy` refusing to delete a
   non-empty ECR repo

## observability

Three CloudWatch alarms, all notifying one SNS topic with an email
subscription:
- `alb-5xx` - more than 5 5xx responses from targets in 1 minute
- `unhealthy-targets` - at least one unhealthy target for 2 minutes straight
- `ecs-high-cpu` - service CPU above 80% for 2 minutes

## resilience

- **deployment circuit breaker**: if a new task definition's tasks fail to
  reach a healthy state, ECS automatically rolls the service back to the
  last known-good task definition instead of leaving it degraded
- **autoscaling**: target tracking on CPU, target 50%, 1-3 tasks. `GET
  /burn?seconds=N` exists specifically to push CPU up and trigger this

`alert_email` lives in `terraform/environments/dev/terraform.tfvars`, which
is gitignored - see `terraform.tfvars.example` for the format.

## terraform

State is local for now (`terraform.tfstate` in `environments/dev`, gitignored).
This was a deliberate scope decision, not an oversight: the GitHub Actions
pipeline never runs `terraform apply` - it only builds the image and updates
the ECS service/task definition directly through the AWS CLI. Infrastructure
changes (new modules, different instance sizes, etc.) still go through
`terraform apply` run by hand. Those two things change at very different
rates, so keeping them on separate paths is fine here. If this were a team
project instead of solo, terraform state would need to move to a remote
backend (S3 + a DynamoDB lock table) so more than one person's local machine
could safely run it.

```
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
# ...look around, confirm the VPC/subnets exist in the console...
terraform destroy
```

## CI/CD (GitHub Actions)

`.github/workflows/deploy.yml` runs on every push to `main` that touches
`app/`:

1. install deps, run `pytest`
2. assume an AWS IAM role via OIDC (`aws-actions/configure-aws-credentials`)
   - no AWS access keys stored in GitHub at all - GitHub issues a short-lived
     OIDC token, AWS trusts it because of the identity provider + role trust
     policy Terraform created (`terraform/modules/github_oidc`), scoped so
     only workflows from this exact repo can assume it
3. build the image (`--platform linux/arm64`, tagged `sha-<git sha>` since
   the ECR repo has immutable tags)
4. push to ECR
5. fetch the current ECS task definition, swap in the new image, register
   it as a new revision, update the service, wait for it to stabilize

One-time setup after pushing this repo to GitHub: go to
**Settings -> Secrets and variables -> Actions -> Variables** and add
`AWS_ROLE_ARN` = the `github_actions_role_arn` terraform output. It's a
plain IAM role ARN, not a secret - it grants nothing on its own without a
valid OIDC token from this repo, which is why it's a *variable* rather than
a *secret*.

The `build-and-deploy` job only runs while `AWS_ROLE_ARN` is set. While the
environment is torn down, delete the variable and pushes still run the tests
without failing on a deploy to infrastructure that doesn't exist.

## running locally

```
cd app
python -m venv venv
venv\Scripts\activate
pip install -r requirements-dev.txt
python app.py
```

```
pytest
```

## running in docker

```
cd app
docker build -t ecs-fargate-pipeline .
docker run -p 8080:8080 ecs-fargate-pipeline
```

## deploying a new image manually

Before the CI/CD pipeline is actually wired up to GitHub, this is done by
hand. The ECR repo has `IMMUTABLE` tags, so every push needs a new tag -
bump it each time (`v2`, `v3`, ...):

```
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

cd app
docker build -t <account-id>.dkr.ecr.us-east-1.amazonaws.com/ecs-fargate-pipeline-app:vN .
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/ecs-fargate-pipeline-app:vN
```

Then update `image_tag` in `terraform/environments/dev/variables.tf` (or
pass `-var image_tag=vN`) and `terraform apply` - this registers a new
task definition revision and updates the service. `terraform apply`
kicks the deployment off but doesn't wait for it; check progress with:

```
aws ecs describe-services --cluster ecs-fargate-pipeline-cluster --services ecs-fargate-pipeline-service --query 'services[0].deployments'
```

The pipeline does this properly with a unique tag per commit
(`sha-<git sha>`) instead of manually bumped version numbers.

## why ARM64

The task definition sets `runtime_platform.cpu_architecture = "ARM64"`
(Graviton). This isn't just because the build machine happens to be ARM -
Graviton Fargate pricing is also about 20% cheaper than the x86 default,
and there was no reason this simple Flask app needed x86-specific
anything.

## why no NAT gateway (for now)

NAT Gateway costs money 24/7 just for existing (~$0.045/hr). To keep this
close to free while learning, the ECS tasks sit in public subnets but with
a security group that only allows inbound traffic from the ALB - so they're
not actually reachable from the internet directly, they just don't need a
NAT Gateway for outbound access. Private subnets + NAT is the "textbook"
setup and is on the list to add later as a documented upgrade.
