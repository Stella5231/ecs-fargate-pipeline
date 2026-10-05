# incident 1: container crash -> ECS self-heals

**goal:** prove that if the running container dies/goes bad, ECS notices
and replaces it without anyone stepping in.

## first three attempts didn't work

`/crash` originally tried to just kill the process:

**attempt 1** - `os._exit(1)` inside the Flask request handler. This only
kills the current **gunicorn worker**. Gunicorn's master process (pid 1 in
the container) just logs `Worker exited with code 1` and boots a
replacement worker. The container itself never stops, so ECS never sees
anything wrong. Confirmed by watching `aws ecs list-tasks` for 90+ seconds
after triggering it - same task ARN the whole time.

**attempt 2** - `os.kill(os.getppid(), signal.SIGKILL)`, targeting the
master directly. In theory this should bring the whole container down.
In practice, still no change to the running task after 90+ seconds. Also
had a real bug alongside it: the function had no `return` statement, so
Flask itself raised `TypeError: did not return a valid response` on every
call (visible in the CloudWatch logs), independent of whether the kill
worked.

**attempt 3** - `os.killpg(os.getpgrp(), signal.SIGKILL)`, targeting the
whole process group instead of just the master pid, with logging added
first to confirm the actual pid/ppid/pgid values (`pid=7 ppid=1 pgid=1` -
so the group id genuinely was 1). This raised
`ProcessLookupError: [Errno 3] No such process`. Best guess: `killpg(1,
sig)` is equivalent to `kill(-1, sig)`, and POSIX `kill(2)` gives `pid ==
-1` a special "broadcast to every process the caller can signal" meaning
that explicitly **excludes pid 1 (init)** - so this wasn't hitting a
container-specific quirk, it was hitting a documented kill(2) edge case
that just happens to bite you specifically when pgid == 1.

## what actually works

Trying to manually signal pid 1 from inside a gunicorn worker turned out
to be the wrong approach entirely, and arguably not realistic either -
production containers usually fail by going unresponsive or by an
in-process bug tripping a health check, not by something inside the app
sending a signal to its own init process.

So `/crash` (see [app/app.py](../../app/app.py)) just flips an in-memory
flag; `/health` starts returning `500` once it's set. The Dockerfile
already had a `HEALTHCHECK` pointed at `/health`, but that alone isn't
enough - **Fargate does not automatically read the image's Docker
`HEALTHCHECK` as the ECS task's health status.** Without an explicit
`healthCheck` block in the task definition itself, ECS never learns the
container is unhealthy and never replaces it (confirmed: task's
`healthStatus` stayed `UNKNOWN` the entire time with only the Dockerfile
healthcheck in place). Added the equivalent check explicitly in
[terraform/modules/ecs/main.tf](../../terraform/modules/ecs/main.tf)'s
container definition, matching the Dockerfile's check.

## the actual run (real timestamps, `us-east-1`)

| time (UTC) | event |
|---|---|
| 17:07:55 | `GET /crash` - app marks itself unhealthy |
| 17:08:38 | ECS reports the task's container `healthStatus` as `UNHEALTHY` (+43s) |
| 17:09:02 | replacement task `e37a89e9...` starts alongside the old one (+67s) |
| 17:09:30 | replacement task is `RUNNING` |
| 17:09:39 | original task moves to `DEACTIVATING` (+104s) |
| ~17:09:50 | new task reports `healthStatus: HEALTHY`, serving traffic |

Total time from crash to a healthy replacement serving traffic: **about
100-115 seconds**, with roughly a 40s detection delay (matches the
healthcheck's `interval=10s, retries=3, startPeriod=10s` config) plus
ECS's own task replacement overhead.

The stopped task's `stoppedReason`:
```
Task failed ELB health checks in (target-group .../ecs-fargate-pipeline-tg)
```
so in this run the ALB's own target-group health check (already
configured, unrelated to the fix above) was what actually triggered the
replacement - it and the new ECS container health check were both
watching `/health` and both would have caught this independently. Worth
being honest about: this means the container-level `healthCheck` fix was
necessary to get an accurate `healthStatus` reading and is still the
right thing to have, but this particular test run couldn't isolate which
one physically stopped the task first at this resolution.

## takeaway

"Add a health check" sounds like a checkbox. In practice: the check has to
be wired into the platform's failure-detection path specifically (Docker
`HEALTHCHECK` in the image is necessary but not sufficient on Fargate -
ECS needs to be told about it too), and the fastest, most "realistic"
crash simulation isn't killing a process at all, it's making the app fail
the same check a real bug would.
