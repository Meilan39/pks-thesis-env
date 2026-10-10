# Flexible I/O Tester (`fio`) Block I/O Microbenchmark

## Upstream Origin & Purpose
- **Tool**: Flexible I/O Tester (`fio-3.33`), standard Linux storage benchmarking utility.
- **Role in Thesis**: Evaluates single-threaded synchronous page-cache write and read latencies across varying block sizes, isolating CPU-level Protection Keys for Supervisor (PKS) permission toggling costs from storage bottlenecks.

---

## Directory Layout
Raw machine-readable JSON transcripts are preserved exclusively for `fio` to allow detailed percentile and distribution analysis across all 12 evaluated block sizes:
```text
perf/fio/
├── run.sh       # Benchmark execution and telemetry extraction
├── README.md    # Reviewer documentation and metric specifications
└── raw/         # Retained raw JSON distributions across variants
    ├── control/ # Baseline kernel sweeps (write_warm, read_warm, write_cold)
    ├── off/     # Ablation kernel sweeps
    └── on/      # Hardware PKS kernel sweeps
```

---

## Applied Patches & Policy Compliance
- **Applied Patches**: None.
- **Verification**: The benchmark invokes the standard Debian distribution package `fio` without custom binary patches or in-tree source modifications.

---

## Benchmark Workload Design

### Block Size Sweep
The evaluation sweeps 12 power-of-two block sizes:
`512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072, 262144, 524288, 1048576` bytes.

### 1. Warm Cache Sweep
- **Configuration**: Synchronous I/O engine (`--ioengine=sync`), buffered I/O (`--buffered=1`, `--direct=0`), in-place overwrite (`--overwrite=1`), cache preservation (`--invalidate=0`), single thread (`--numjobs=1`, `--thread=1`), 32 MiB file size.
- **Mechanism**: Pre-populates the 32 MiB target file in memory, followed by in-place sequential overwrites and sequential reads. Before the run, dirty ratios are tuned to prevent background flusher interference, and a sync pass between block sizes prevents writeback queuing.
- **Purpose**: Measures pure memory access latency and thread-local PKRS MSR register updating cost on in-cache resident pages, completely bypassing disk I/O and cache invalidation.

### 2. Cold Cache Sweep
- **Configuration**: Synchronous write, dropped page cache (`drop_caches=3` and `sync`) and file removal prior to each block size iteration, forcing cache eviction (`--invalidate=1`).
- **Mechanism**: Writes to a newly allocated file, forcing the kernel to allocate and zero fresh page-cache frames from the buddy allocator or static PKS pool.
- **Allocation Cost Metric**: The difference between cold and warm write latencies (`lat4k_cold_write_us - lat4k_warm_write_us`) quantifies the additional time required to assign and protect direct-map pages in the supervisor pool during page-fault allocation paths.

---

## Output Contract & Telemetry
The benchmark runner extracts key metrics from the raw JSON outputs and emits a single structured status line:
```text
STATUS node=fio variant=<control|off|on> verdict=PASS iops4k_warm_write=<iops> lat4k_warm_write_us=<lat> lat4k_warm_read_us=<lat> lat4k_cold_write_us=<lat> alloc_overhead_us=<delta> bw1m_seq_read_kbs=<bw>
```

Field descriptions:
- `iops4k_warm_write`: 4 KiB warm write IOPS.
- `lat4k_warm_write_us`: Mean 4 KiB warm write latency in microseconds.
- `lat4k_warm_read_us`: Mean 4 KiB warm read latency in microseconds.
- `lat4k_cold_write_us`: Mean 4 KiB cold write latency in microseconds.
- `alloc_overhead_us`: Allocation cost delta (`lat4k_cold_write_us - lat4k_warm_write_us`) in microseconds.
- `bw1m_seq_read_kbs`: 1 MiB sequential read throughput in KiB/s.
