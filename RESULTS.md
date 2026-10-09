# Hosted runner benchmark: GitHub-hosted, Depot, Namespace, WarpBuild

Measured on 2026-10-06 in this repo, on a free-plan GitHub organization. Every
number comes from the workflows in `.github/workflows/`, which differ only in
the `runs-on` label.

## What was measured

A small CI-like job: `actions/checkout@v4`, `actions/setup-node@v4` with Node 22,
then `npm ci --ignore-scripts` on the lockfile in `gha-bench/` (387 packages).
Step durations come from the GitHub jobs API, so the resolution is 1 s.

- Dispatch to done is the job's `completed_at` minus `created_at`.
- Start gap is the first step's start minus the job's `started_at`. GitHub marks
  a job started when a runner is assigned, which can be well before the runner
  is ready.
- `gha-bench/micro.sh` is a microbenchmark: `npm ci` cold and with a warm npm
  cache on three filesystems, a 3e8 iteration Node loop, and 3000 small files.
- The cache test saves and restores random data with `actions/cache@v4`
  (random, because zeros compress to nothing). One run misses and saves, the next
  hits and restores. Three rounds at 1 GB and 2 GB.

| Runner | `runs-on` | Shape |
| --- | --- | --- |
| GitHub-hosted | `ubuntu-24.04` | 2 vCPU, varies per job: Xeon Platinum 8573C, AMD EPYC 7763, 9V45 or 9V74 |
| Depot | `depot-ubuntu-24.04` | 2 vCPU, AMD EPYC 9R45 (every run) |
| Namespace | `namespace-profile-emil` | 4 vCPU, 8 GB, AMD EPYC |
| WarpBuild | `warp-ubuntu-2404-x64-4x` | 4 vCPU, 16 GB, Ryzen 9 9950X or 7950X3D |

## CI job, five rounds each

| Runner | Dispatch to start | Start gap | Dispatch to done | checkout | setup-node | npm ci |
| --- | --- | --- | --- | --- | --- | --- |
| GitHub-hosted | 2 to 4 s | 0 to 1 s | 14 to 21 s | 1 s | 0 to 1 s | 7 to 9 s |
| WarpBuild | 4 to 15 s | 0 to 1 s | 13 to 26 s | 1 s | 0 s | 4 to 5 s |
| Namespace | 1 to 15 s | 0 to 1 s | 15 to 41 s | 0 to 2 s | 1 to 24 s | 4 to 13 s |
| Depot | 1 to 4 s | 21 to 32 s | 40 to 58 s | 5 to 7 s | 3 to 6 s | 4 to 6 s |

- Depot reports the job as started within 1 to 4 s, but the runner needs another
  21 to 32 s before the first step. Compare dispatch to done, not the queue time.
- Depot told us it is moving its runners to Depot Metal, which starts much
  faster, and that some jobs still run on its previous architecture, one EC2
  instance per job. Their UI marks Metal runs with a lightning bolt. GitHub's API
  does not show which path a job used and these runs were not checked in Depot's
  UI. The AMD EPYC 9R45 is an AWS CPU and the start gap was a steady 21 s in four
  of five runs, so these runs most likely used the older path. Treat Depot's start
  numbers here as the previous architecture, not Metal.
- Depot's larger sizes did not help this job. At 4, 8 and 16 vCPU (two rounds,
  all three sizes at once) the start gap was 21 to 61 s, dispatch to done 61 to
  98 s, and `npm ci` stayed at 4 to 5 s. The job is single threaded.
- Namespace varied the most between rounds, mostly in setup-node and `npm ci`.
  A second job in the same workflow run never got a runner (queued over five
  minutes), so the Namespace workflows have one job each.
- WarpBuild's jobs stayed queued until the WarpBuild account was fully set up on
  their side. Installing the GitHub app alone was not enough.

## Microbenchmark

| Runner | CPU loop | `npm ci` cold | `npm ci` warm cache | 3000 small files |
| --- | --- | --- | --- | --- |
| Namespace | 0.30 to 0.32 s | 3.7 to 4.8 s | 1.9 to 2.4 s | 49 to 77 ms |
| WarpBuild | 0.35 s | 4.2 to 5.0 s | 1.8 to 2.5 s | 51 to 124 ms |
| Depot | 0.36 s | 4.0 to 5.1 s | 1.2 to 1.35 s | 48 to 53 ms |
| GitHub-hosted | 0.36 to 0.58 s | 5.7 to 8.2 s | 2.4 to 4.7 s | 146 to 276 ms |

Five runs each for GitHub-hosted and Depot, two each for Namespace and WarpBuild.
The CPU model is read from `/proc/cpuinfo` inside the job.

- Depot's 2 vCPU runner (AMD EPYC 9R45 every time) was the fastest 2 vCPU option
  and the most consistent: the CPU loop varied by 5 ms over five runs.
- GitHub-hosted hardware changed from job to job. Five runs landed on four
  different CPUs (Xeon 8573C once, EPYC 7763 twice, EPYC 9V45 once, EPYC 9V74
  once), so its numbers spread widely. The EPYC 7763 runs were the slowest, with
  a warm-cache `npm ci` of 4.3 to 4.7 s against 1.2 to 1.35 s on Depot.
- This matches the CI job, where `npm ci` took 7 to 9 s on GitHub-hosted and 4 to
  6 s on Depot.

## actions/cache, 1 GB and 2 GB

Restore is the "hit" run, save is the "miss" run. Namespace ran without a cache
volume.

| Runner | Restore 1 GB | Restore 2 GB | Save 1 GB | Save 2 GB |
| --- | --- | --- | --- | --- |
| Depot | 6 s | 12 to 17 s | 13 s | 24 to 30 s |
| GitHub-hosted | 19 to 23 s | 23 to 36 s | 7 to 17 s | 29 to 31 s |
| WarpBuild, `WarpBuilds/cache@v1` | 18 to 25 s | 19 to 40 s | 21 to 26 s | 36 to 48 s |
| WarpBuild, plain `actions/cache` | 8 to 54 s | 17 to 130 s | 4 to 8 s | 8 to 40 s |
| Namespace | 18 to 57 s | 39 to 85 s | 6 s | 9 to 26 s |

Restore throughput, median: Depot about 170 MB/s, GitHub-hosted 50 to 60 MB/s,
Namespace 25 to 33 MB/s.

- Depot is the only runner clearly better at restoring a large cache, about three
  times faster than GitHub-hosted here. Its saves match GitHub-hosted.
- WarpBuild and Namespace save fast and restore slowly and unevenly with plain
  `actions/cache`. WarpBuild's 2 GB restore took 17 s, 123 s and 130 s in three
  rounds. `WarpBuilds/cache@v1` restores more steadily but saves slower, and does
  not match Depot.
- Restore time grows roughly with size. Nothing above 2 GB was measured.

## Summary

| | Start | Compute | Large cache restore |
| --- | --- | --- | --- |
| GitHub-hosted | fast | varies by job, slowest on average | middle |
| WarpBuild | fast | fast | uneven, slow saves with its own action |
| Namespace | fast but variable | fastest per core | slow and uneven without a cache volume |
| Depot | slow in this test (21 to 32 s gap, see the note on Depot Metal) | fast and consistent | fastest |

## Caveats

- One afternoon, a free plan, default settings, and a small single threaded job.
  Three to five samples per cell, 1 s resolution. Treat the ranges as rough.
- Depot's own claim is "up to 3x faster than a GitHub-hosted runner". This test
  does not exercise what that claim targets: heavy parallel builds, Docker builds
  and large cache restores. It only says Depot does not help a short job.
- Not tested yet: skipping `setup-node` and using the preinstalled Node (Depot's
  suggestion), and Depot CI, which runs the same workflow files from a `.depot`
  folder without GitHub webhooks.
- Not tested: Namespace's cache volume or base image, Depot's and WarpBuild's
  larger sizes on a parallel workload, anything above 2 GB of cache, and paid
  plans, which may start faster than a free plan.
- The runners were measured at different times of the afternoon. Rounds for
  different vendors often ran side by side, which is fair for network
  conditions but not controlled.

## Reproduce

Dispatch a workflow with `gh workflow run bench-depot.yml`. The cache workflows
take `size_mb` and `round` inputs: run once to save, once to restore, for
example `gh workflow run cache-bench-gh.yml -f size_mb=1024 -f round=1`.

## Corrections

2026-10-09: an earlier version of this file had the CPU models and the
microbenchmark rows for GitHub-hosted and Depot swapped, and listed single samples.
A Depot engineer spotted it. The rows now come from all five runs of each. The CI
job numbers were not affected.
