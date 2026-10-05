# incident 3: load test -> autoscaling

**goal:** push CPU up with `GET /burn` and watch ECS service autoscaling
actually add a task, not just watch a graph move.

## generating load

`/burn?seconds=25` busy-loops the process for 25 seconds. Gunicorn only
runs 1 worker by default, so instead of firing requests in parallel (which
would just queue behind the one worker), a script called `/burn` back to
back in a loop for several minutes straight to keep that one worker
continuously pegged.

## first attempt: target hovered right at 50%, didn't breach

With the autoscaling target at its normal value (50%), sustained load held
`AWS/ECS CPUUtilization` right around 50-52% - technically at the edge,
but target tracking scales out when the metric is *sustained above* the
target with margin, and it stayed too close to the line to reliably
cross it within a normal test window.

## second attempt: lowered the target to 30% to get a clean signal

This is a legitimate way to test that a scaling pipeline actually works,
not cheating the result - same idea as temporarily lowering an alert
threshold to confirm the alert fires. Changed
`autoscaling_target_cpu` from 50 to 30 in
[terraform/environments/dev/variables.tf](../../terraform/environments/dev/variables.tf),
applied, kept the load running.

### what actually happened (`us-east-1`, real timestamps)

| time (UTC) | event |
|---|---|
| 17:17:00 | sustained `/burn` load begins (round 2, after round 1 wasn't long enough) |
| 17:19:16 | `terraform apply` lowers the CPU target from 50% to 30% |
| 17:20:07 | scaling alarm `...-AlarmHigh` in `ALARM` - 3 datapoints (49.9%, 52.1%, 52.2%) over threshold (30%) |
| 17:20:07 | `desiredCount` already at 2 (scaling decision made same moment as detection) |
| ~17:20:35 | 2nd task registered as a target on the ALB |
| ~17:20:51 | `runningCount` reaches 2, both targets report `healthy` |

Total time from the alarm entering `ALARM` to a second healthy task
serving traffic: **under a minute**. Scaling out is fast once CloudWatch
actually decides to act - the slow part in the earlier attempt was purely
getting a clean breach signal.

### an unplanned second finding

Service events also showed this, from the same load window:
```
(task 3fbb2e0bb98c45e48614752492a4cb78) (port 8080) is unhealthy in
(target-group .../ecs-fargate-pipeline-tg) due to (reason Request timed out).
```
The *original* task got marked unhealthy and was replaced - not because
of a real problem with it, but because gunicorn's single synchronous
worker was still busy running a 25-second `/burn` request when the ALB's
health check tried to hit `/health` on the same worker. The health check
timed out waiting behind it, tripped the `unhealthy_threshold`, and ECS
stopped that task and started a fresh one.

This is a real, useful finding, not a bug in the test: it's the practical
argument for why a single sync worker isn't a realistic production config
for anything that does blocking work per-request - either run multiple
workers/threads so health checks don't queue behind slow requests, or use
an async worker class. Not fixing it here since `/burn` blocking on
purpose is the whole point of that endpoint, but worth knowing that this
app's current gunicorn config (`gunicorn app:app`, no `--workers` flag,
defaults to 1) would need that change before handling real concurrent
traffic.

## cleanup

Set `autoscaling_target_cpu` back to 50 and `terraform apply`'d again once
the evidence above was captured. Confirmed scale-in also works without any
manual intervention - by the time the load generator finished and CPU
dropped, `desiredCount`/`runningCount` were both back to 1 on their own,
consistent with the policy's `scale_in_cooldown` of 120s.

## takeaway

Load-testing against a real deployed service surfaces things a
`terraform plan` never will - the gunicorn worker-count issue above only
showed up because there was an actual concurrent health check racing an
actual busy request on real infrastructure.
