# Benchmark scenario

Compare two Azure Container Apps Flex topologies for request throughput using the same upstream-bound Node.js simulation workload and Premium ingress.

| Scenario | Requested topology | Deployed Flex-compatible topology |
|---|---|---|
| Littles | 32 replicas at 0.5 vCPU / 1 GiB | 32 replicas at 0.5 vCPU / 2 GiB, one Node process each |
| Bigs | 16 replicas at 1 vCPU / 2 GiB with PM2 | 16 replicas at 1 vCPU / 4 GiB, two PM2 workers each |

The requested memory sizes are invalid for Flex. The deployed topology preserves CPU, replica counts, total Node workers, and the intended comparison while using the required 1:4 CPU-to-memory ratio.

## Controls

- Static app replica counts; no autoscaling.
- Fixed Premium ingress capacity.
- Separate environment, VNet, and private Blob upstream for each scenario.
- Same source, base image, request behavior, and regional placement.
- Four Azure Load Testing engines using one environment-driven JMeter plan.
- Warm-up followed by paired high-concurrency runs.

## Success criteria

- Record enough paired results to explain the throughput difference.
- Verify replica counts, restarts, upstream health, and load-generator headroom.
- Preserve sanitized evidence and a reproducible deployment and benchmark workflow.
