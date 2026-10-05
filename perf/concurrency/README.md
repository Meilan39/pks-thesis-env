# Multi-Threaded Write Concurrency Benchmark

## Upstream Origin & Purpose
- **Tool**: Flexible I/O Tester (`fio-3.33`), multi-threaded buffered write configuration.
- **Role in Thesis**: Evaluates parallel synchronous page-cache write scalability across 1, 2, and 4 CPU cores. Validates that thread-local Protection Keys for Supervisor (PKS) permission updates (via IA32_PKRS MSR) scale without global lock serialization, cross-core cache invalidations, or inter-processor interrupts (IPIs).

---

## Directory Layout
Raw per-thread JSON dumps are eliminated from the source tree; all extracted throughput metrics are logged directly to [`perf/result.csv`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/perf/result.csv):
```text
perf/concurrency/
├── run.sh       # Benchmark execution and scaling efficiency extraction
└── README.md    # Reviewer documentation and metric specifications
```

---

## Applied Patches & Policy Compliance
- **Applied Patches**: None.
- **Verification**: The benchmark invokes the standard Debian distribution package `fio` without custom binary patches or in-tree source modifications.

---

## Benchmark Workload Design

### Thread Scaling Sweep
The benchmark evaluates 1, 2, and 4 concurrent worker threads:
1. Prior to each job count sweep, disk caches are synchronized and dropped (`drop_caches=3`).
2. Each thread pre-allocates an independent 16 MiB file on the protected filesystem (`/mnt/protected`).
3. Threads execute synchronous buffered 4 KiB writes (`--rw=write --bs=4k --size=16m --ioengine=sync --buffered=1`) concurrently.

### Scaling Efficiency
Multi-core scaling efficiency isolates parallel degradation:
$$\text{Scaling Efficiency (\%)} = \frac{\text{Throughput}_{\text{4 threads}}}{4 \times \text{Throughput}_{\text{1 thread}}} \times 100$$
A linear scaling efficiency close to 100% demonstrates that PKS key management executes strictly within local core registers without inter-core cache-line contention.

---

## Output Contract & Telemetry
Intermediate JSON results are generated in `/tmp` during execution and purged upon completion. The runner emits a single structured status line:
```text
STATUS node=concurrency variant=<control|off|on> verdict=PASS bw_1t_mbps=<bw1> bw_2t_mbps=<bw2> bw_4t_mbps=<bw4> scaling_pct=<eff>
```

Field descriptions:
- `bw_1t_mbps`: Aggregate write throughput with 1 worker thread (MB/s).
- `bw_2t_mbps`: Aggregate write throughput with 2 worker threads (MB/s).
- `bw_4t_mbps`: Aggregate write throughput with 4 worker threads (MB/s).
- `scaling_pct`: 4-thread parallel scaling efficiency percentage.
