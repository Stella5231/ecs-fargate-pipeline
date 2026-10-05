# incident 2: security misconfiguration + drift detection

**goal:** show what happens when someone makes a manual, out-of-band
change that weakens security, and how Terraform catches it.

## the setup

The ECS tasks sit in public subnets (see the "why no NAT gateway" section
in the root README) but are supposed to be locked down at the security
group level - only the ALB's security group is allowed to reach them on
port 8080. Direct internet access to a task's own public IP should fail.

Confirmed this first, before touching anything:
```
2026-08-18T17:12:40Z
curl --max-time 8 http://<task public ip>:8080/health
-> connection timed out (as expected)
```

## the mistake

Simulated an operator manually "fixing connectivity" through the AWS
console/CLI directly, bypassing Terraform entirely:

```
aws ec2 authorize-security-group-ingress \
  --group-id sg-031a49b30bc7d4109 \
  --protocol tcp --port 8080 --cidr 0.0.0.0/0
```

Confirmed the task was now directly reachable from the internet,
completely bypassing the ALB:

```
2026-08-18T17:14:00Z
curl http://<task public ip>:8080/health
-> {"status":"ok"}   (200 - reachable, should not be)
```

## catching it

This is exactly what `terraform plan` is for. Since the security group's
`ingress` rules are managed as a complete declarative list in
[terraform/modules/ecs/main.tf](../../terraform/modules/ecs/main.tf),
any rule that exists in AWS but isn't in the `.tf` file shows up as drift:

```
module.ecs.aws_security_group.ecs_tasks will be updated in-place
  ~ ingress = [
      - {
          - cidr_blocks = ["0.0.0.0/0"]
          - from_port   = 8080
          - protocol    = "tcp"
          - to_port     = 8080
        },
      # (1 unchanged element hidden)
    ]

Plan: 0 to add, 1 to change, 0 to destroy.
```

`terraform apply` removed the manual rule and restored the group to
exactly what the code says it should be. Confirmed the bypass was closed:

```
2026-08-18T17:15:00Z
curl --max-time 8 http://<task public ip>:8080/health
-> connection timed out again
```

Total exposure window: about **75 seconds**, start to fix.

## takeaway

Infrastructure as code isn't just "faster provisioning" - it's a
correctness net. A manual console change that would otherwise sit there
silently (until someone happens to notice or gets scanned) shows up as an
explicit, reviewable diff the next time anyone runs `plan`. This is also
the practical argument for running `terraform plan` on a schedule /
in CI even when nothing is being actively deployed, so drift like this
doesn't sit undetected for days.
