# Littles vs. Bigs benchmark outcome

**Test date:** October 6, 2026

**Region:** South Central US

**Result:** **Bigs was the better high-concurrency topology in all four paired runs.** It delivered 23.04% more mean throughput in the original three-run set, 13.29% more throughput in an extended five-million-request validation pair, and 18.77% more throughput across all measured time.

## Important Flex sizing constraint

The originally requested sizes cannot be deployed on the Azure Container Apps Flex workload profile:

- Requested Littles: `0.5 vCPU / 1 GiB`
- Requested Bigs: `1 vCPU / 2 GiB`
- Flex-compatible combinations reported by Azure include `0.5 vCPU / 2 GiB` and `1 vCPU / 4 GiB`.

The benchmark therefore preserved the requested replica counts and CPU allocation, using the user-approved Flex-compatible memory sizes:

| Scenario | Replicas | Per replica | Node workers | Total target allocation |
|---|---:|---:|---:|---:|
| Littles | 32 | 0.5 vCPU / 2 GiB | 1 per replica | 16 vCPU / 64 GiB |
| Bigs | 16 | 1 vCPU / 4 GiB | 2 PM2 workers per replica | 16 vCPU / 64 GiB |

This result compares the requested **32 smaller replicas** topology with the **16 larger PM2 replicas** topology on Flex. It does not measure the effect of the originally requested lower memory limits because Flex rejects those limits.

## Test topology

- Two isolated Azure Container Apps environments:
  - One dedicated to Littles.
  - One dedicated to Bigs.
- Both app environments used:
  - Flex workload profile for the benchmark app.
  - Premium ingress on a dedicated `D4` workload profile.
  - Fixed Premium ingress capacity: minimum 2 nodes, maximum 2 nodes.
  - Fixed app replicas: minimum and maximum both set to 32 or 16.
- The same Node.js source and base image were used:
  - `simulation-app:single`
  - `simulation-app:pm2`
- The PM2 image ran exactly two cluster workers per replica, giving both scenarios 32 Node workers in total.
- Each request fetched a small object from a scenario-specific private regional Blob Storage endpoint and then awaited 40 ms.
- Azure Load Testing generated the traffic with four JMeter engines.

An earlier Bigs environment provisioning attempt stalled during Azure control-plane initialization and never created its managed infrastructure resource group. The successful replacement used the same configuration on a fresh VNet, and the reusable template now creates the two environments sequentially.

## Load profile

| Phase | Load | Duration | Ramp |
|---|---:|---:|---:|
| Warm-up | 100 users per engine, 400 total | 60 seconds | 10 seconds |
| Measurement | 500 users per engine, 2,000 total | 180 seconds | 15 seconds |

The measurement order alternated Littles then Bigs for three pairs.

Request totals came from Azure Load Testing's `TotalRequests` metric. Mean latency was request-weighted across five-minute metric buckets. Each run's p95 and p99 use the highest five-minute bucket value when a run crossed a bucket boundary, making the reported tail latency conservative.

## Warm-up result

At moderate concurrency, the scenarios were effectively tied:

| Scenario | Requests | Throughput | Mean | p95 | p99 | Errors |
|---|---:|---:|---:|---:|---:|---:|
| Littles | 424,544 | 7,075.73 RPS | 51 ms | 55 ms | 80 ms | 0 |
| Bigs | 426,909 | 7,115.15 RPS | 51 ms | 53 ms | 81 ms | 0 |

Bigs was only 0.56% faster during warm-up. The material difference appeared under the 2,000-user measurement load.

## Measurement runs

| Pair | Scenario | Requests | Throughput | Mean | p95 | p99 | Error rate |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | Littles | 2,167,949 | 12,044.16 RPS | 159.00 ms | 285 ms | 2,932 ms | 0.04276% |
| 1 | Bigs | 2,719,887 | 15,110.48 RPS | 127.19 ms | 183 ms | 1,666 ms | 0.01118% |
| 2 | Littles | 2,160,284 | 12,001.58 RPS | 161.00 ms | 344 ms | 3,270 ms | 0.05481% |
| 2 | Bigs | 2,774,391 | 15,413.28 RPS | 125.00 ms | 169 ms | 1,356 ms | 0.00624% |
| 3 | Littles | 2,232,384 | 12,402.13 RPS | 154.93 ms | 263 ms | 3,254 ms | 0.04551% |
| 3 | Bigs | 2,578,067 | 14,322.59 RPS | 133.23 ms | 185 ms | 2,432 ms | 0.02490% |

Bigs improved throughput by 25.46%, 28.43%, and 15.48% in the three paired runs. Its slowest run still exceeded the fastest Littles run by 1,920.46 RPS.

## Aggregate comparison

| Metric | Littles | Bigs | Bigs difference |
|---|---:|---:|---:|
| Mean throughput | 12,149.29 RPS | 14,948.79 RPS | **+23.04%** |
| Throughput sample standard deviation | 220.00 RPS | 563.04 RPS | Bigs was more variable |
| 95% CI for mean throughput | 11,602.78–12,695.80 | 13,550.13–16,347.45 | Non-overlapping |
| Total requests over 3 runs | 6,560,617 | 8,072,345 | **+1,511,728** |
| Mean response time | 158.31 ms | 128.47 ms | **-18.85%** |
| Average p95 | 297.33 ms | 179.00 ms | **-39.80%** |
| Average p99 | 3,152 ms | 1,818 ms | **-42.32%** |
| Weighted error rate | 0.04766% | 0.01386% | **-70.92%** |

The paired throughput difference averaged **2,799.50 RPS**. Its 95% confidence interval was **+860.36 to +4,738.64 RPS**, so all of the interval favored Bigs despite the small sample count.

## Extended five-million-request validation

One additional pair used the same four engines, 500 users per engine, and 15-second ramp, but extended each measurement to 420 seconds. Both scenarios exceeded five million requests.

| Scenario | Requests | Throughput | Mean | p95 | p99 | Errors | Error rate |
|---|---:|---:|---:|---:|---:|---:|---:|
| Littles | 5,120,553 | 12,191.79 RPS | 160.90 ms | 263 ms | 3,186 ms | 6,795 | 0.13270% |
| Bigs | 5,801,018 | 13,811.95 RPS | 141.29 ms | 188 ms | 2,364 ms | 2,589 | 0.04463% |

In the extended pair, Bigs:

- Processed **680,465 additional requests**.
- Delivered **13.29% more throughput**.
- Reduced mean latency by **12.19%**.
- Reduced p95 by **28.52%** and p99 by **25.80%**.
- Reduced the error rate by **66.37%**.

All extended-run failures were again HTTP 502 responses. Load-engine CPU peaked at 59.3% for Littles and 67.9% for Bigs, leaving generator headroom. Post-run checks confirmed all 32 Littles replicas and all 16 Bigs replicas were running.

Across the original three pairs plus the extended pair, each scenario ran for 960 measured seconds:

| Combined metric | Littles | Bigs | Bigs difference |
|---|---:|---:|---:|
| Requests | 11,681,170 | 13,873,363 | **+2,192,193** |
| Time-weighted throughput | 12,167.89 RPS | 14,451.42 RPS | **+18.77%** |
| Weighted error rate | 0.08494% | 0.02673% | **-68.53%** |

## Validity checks

- **No app scaling:** Azure Monitor recorded exactly 32 Littles replicas and 16 Bigs replicas throughout the measurement window.
- **No restarts:** both apps recorded zero replica restarts.
- **No upstream throttling:** Blob Storage metrics contained only successful response types:
  - Littles upstream: 6,559,867 successful transactions.
  - Bigs upstream: 8,072,023 successful transactions.
- **Load generators retained headroom:** in representative high-load runs, Azure Load Testing engine CPU averaged 51.6% for Littles and 63.1% for Bigs, with maximums of 68.0% and 80.6%. The engines sustained 500 users per engine.
- **Same low-load baseline:** the nearly identical warm-up results show that DNS, ingress, storage, and basic request behavior were comparable before the targets were stressed.
- **Errors were consistent:** all measured failures were HTTP 502 responses from the simulation app's upstream-fetch failure path. Bigs produced 1,119 errors versus 3,127 for Littles.

## Interpretation

The result supports the following topology-level explanation:

1. A Littles Node process is constrained by a 0.5-vCPU cgroup. Short CPU bursts from TLS, HTTP parsing, response handling, and event-loop work can exhaust that smaller quota even when minute-level average CPU is not 100%.
2. Each Bigs replica lets two PM2 workers share a 1-vCPU cgroup. This provides more burst headroom and allows one worker to use capacity while the other is awaiting upstream I/O.
3. Bigs uses half as many replicas and container networking contexts for the same total CPU, memory, and Node worker count, reducing per-replica runtime and networking overhead.
4. The scenarios were tied at 400 users but separated consistently at 2,000 users. That load-dependent pattern is consistent with scheduling and per-replica overhead becoming material under concurrency.

This benchmark intentionally changes both replica size and process management, so it establishes that the complete **Bigs + PM2 topology** is better for this workload. It does not isolate PM2 as the sole cause. A separate 16-replica, 1-vCPU single-process control would be required to measure PM2's independent contribution.

## Conclusion

For this upstream-bound, low-CPU Node workload on Flex with static scale and Premium ingress, choose **Bigs: 16 replicas with two PM2 workers per replica**. It won all four high-load pairs and produced **18.77% more requests per second across the combined 960 measured seconds**, with materially better tail latency and fewer errors while using the same total target CPU, memory, and Node worker count.

## Evidence

- Sanitized per-run results: [`results/2026-10-06/runs.csv`](results/2026-10-06/runs.csv)
- Statistical summary: [`results/2026-10-06/statistical-summary.json`](results/2026-10-06/statistical-summary.json)
- Monitoring and error summary: [`results/2026-10-06/monitor-summary.json`](results/2026-10-06/monitor-summary.json)
- Extended and combined summary: [`results/2026-10-06/extended-monitor-summary.json`](results/2026-10-06/extended-monitor-summary.json)

The tracked evidence excludes subscription identifiers, Azure portal URLs, SAS URLs, raw result artifacts, and machine-local paths.
