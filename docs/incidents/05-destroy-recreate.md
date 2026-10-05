# incident 5: destroy -> recreate

**goal:** prove the environment isn't held together by anything that
only exists in the AWS console - `terraform destroy` then `terraform
apply` should get back to the exact same working state.

## what was supposed to happen

```
terraform destroy   # tear everything down
terraform apply     # bring it all back
```
cleanly, in that order.

## what actually happened

`terraform destroy` (started 17:45:52 UTC) tore down 20 of 21 resources -
VPC, subnets, ALB, ECS service/cluster/task definitions, IAM roles, the
OIDC provider, CloudWatch alarms, the SNS topic - and then failed on the
last one:

```
Error: ECR Repository (ecs-fargate-pipeline-app) not empty, consider
using force_delete: RepositoryNotEmptyException
```

The ECR repo still had the images from every incident in this doc
(`v2` through `v4`, `broken`) and Terraform won't delete a non-empty
repository by default. Fair enough - that's a reasonable guardrail for a
repo holding anything you'd actually care about losing. For this project
specifically it's fine, so
[terraform/modules/ecr/main.tf](../../terraform/modules/ecr/main.tf) got
`force_delete = true` added, with a comment noting that's a deliberate
call for a demo repo, not a default anyone should reach for casually.

Running `terraform apply` after that fix didn't just fix the ECR repo -
since the *rest* of the infrastructure was already gone from state and
reality, Terraform recreated the entire stack from a clean slate: new
VPC (`vpc-09dc0b8e...`, different id from before), new subnets, a new ALB
with a **new DNS name**
(`ecs-fargate-pipeline-alb-1275605774.us-east-1.elb.amazonaws.com`,
different from the original `...-580087848...`), new IAM roles, new
CloudWatch alarms - everything, purely from the `.tf` files, no manual
console steps.

The ECR repo itself was never actually destroyed (it survived the whole
sequence), so the previously-pushed `v4` image was still there, and the
freshly-created ECS service pulled it and came up healthy without
needing a rebuild.

Confirmed against the new environment:
```
curl http://ecs-fargate-pipeline-alb-1275605774.../
-> {"hostname":"ip-10-0-2-117...","service":"aws-devops-portfolio-demo"}
curl http://.../health
-> {"status":"ok"}
```

Time from `desiredCount` being set on the recreated service to
`runningCount` reaching 1 and reporting healthy: well under 5 minutes.

## takeaway

This didn't go exactly as planned, and that's more useful than if it had.
The real result still holds - nothing in this environment depends on
manual console setup, everything comes back from `terraform apply` alone
- but it also surfaced a genuine gap (ECR's default delete protection)
that a clean, scripted "destroy then apply" run wouldn't have caught.
Worth remembering for next time: run `terraform destroy` and actually
read whether it succeeded, not just whether the command exited.
