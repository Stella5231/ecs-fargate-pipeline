# incident 4: bad deploy -> automatic rollback

**goal:** deploy a genuinely broken image and confirm the ECS deployment
circuit breaker (added in
[terraform/modules/ecs/main.tf](../../terraform/modules/ecs/main.tf))
actually rolls back on its own, with zero downtime for real traffic.

## the broken build

[Dockerfile.broken-example](Dockerfile.broken-example) is the real app,
except the last line binds gunicorn to the wrong port:
```
CMD ["gunicorn", "--bind", "0.0.0.0:9999", "app:app"]
```
The task definition's health check and port mapping both expect `8080`.
The container starts fine and doesn't crash - it just never answers on
the port anything is actually checking, which is a fairly realistic way
for a "bad deploy" to look in practice (as opposed to a container that
crashes outright, which is a different, earlier incident).

Built and pushed as tag `broken`, set `image_tag = "broken"` in
`terraform/environments/dev/variables.tf`, `terraform apply`.

## real timeline (`us-east-1`)

| time (EDT) | event |
|---|---|
| 13:25:53 | `terraform apply` deploys the broken image (task def revision `:7`) |
| 13:26:11 | new deployment created, `desiredCount=1` |
| 13:30:41 | first task attempt actually starts (~4.5 min Fargate scheduling delay - slower than expected, worth knowing about for future load-sensitive demos) |
| ~13:31:33 | that task fails its health check, starts deactivating |
| by 13:35:52 | a 2nd attempt has also failed (`failedTasks: 2`) |
| 13:38:24 | 3rd attempt (task `4c423a38...`) fails container health checks, stopped |
| 13:38:34 | ECS declares the deployment failed (`"tasks failed to start"`) and begins automatic rollback |
| 13:39:36 | rollback deployment completed - service back on the last good task definition (`:6`, the `v4` image) |

**Total time from bad deploy to fully-automatic recovery: ~13m 43s,
across 3 failed task attempts.** The circuit breaker doesn't give up after
one failure - it retries a few times first, which is reasonable (avoids
rolling back on a one-off transient failure) but means this took longer
than the crash-recovery incident.

**Downtime during all of this: zero.** The old task (running the good
`v4` image, revision `:6`) was never touched - min/max healthy percent
(100%/200%) keeps it serving the whole time a new revision is being
tried. Confirmed with real requests during the failed deploy:
```
curl http://.../
-> {"hostname":"ip-10-0-2-150...","service":"aws-devops-portfolio-demo"}
```

## the part that isn't automatic: reconciling Terraform afterward

ECS's circuit breaker rolled the *service* back on its own, but it did
this entirely inside AWS - Terraform has no idea it happened. Terraform's
state still said the desired task definition was revision `:7` (the
broken one). Running `terraform plan` right after confirmed this:

```
module.ecs.aws_ecs_task_definition.app must be replaced
  ~ image: ".../ecs-fargate-pipeline-app:broken" -> (still what state expects)
```

Left alone, the *next* `terraform apply` - for something completely
unrelated, weeks later - would have quietly redeployed the broken image
again, because as far as Terraform's state is concerned nothing ever
changed. Fixed by setting `image_tag` back to `v4` and applying, which
registered a fresh revision (`:8`, functionally identical to `:6`) and
brought Terraform's state back in sync with reality.

## takeaway

The circuit breaker is real safety, but it's scoped to the ECS service,
not to the IaC that describes it. "Automatic rollback" doesn't mean the
incident is fully closed - someone (or some later pipeline run) still
needs to update the source of truth, or the same bad deploy is one
`terraform apply` away from happening again.
