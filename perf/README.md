# Performance & Overhead Evaluation Axis (`perf/`)

## Executive Summary
The performance axis quantifies the execution overheads introduced by Protection Keys for Supervisor (PKS) page-cache write protection across micro- and macro-level workloads.

Protecting the direct-map page cache requires dynamic permission switching via the `IA32_PKRS` MSR on every supervisor write path (e.g., `copy_from_iter`, `page_mkwrite`, `truncate`). The evaluation measures:
1. Single-threaded synchronous block I/O latency across 12 block sizes from 512B to 1MB under warm and cold cache conditions ([`fio`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/perf/fio/README.md)).
2. Multi-threaded write throughput and parallel scaling efficiency across 1, 2, and 4 CPU cores ([`concurrency`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/perf/concurrency/README.md)).
3. Macro-level database transaction processing throughput and latency under rollback-journal ACID commitments ([`sqlite`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/perf/sqlite/README.md)).

---

## Suite Structure & Reviewer Guides

```text
perf/
├── fio/          # Block I/O microbenchmark (warm & cold sweeps across 12 block sizes)
├── concurrency/  # Multi-threaded page-cache write scalability (1, 2, 4 threads)
├── sqlite/       # Rollback-journal database macrobenchmark (sync=FULL and sync=OFF)
├── analyze.py    # Metric synthesis generating results/data/perf_summary.csv
├── run.sh        # Host aggregator script with 3-tier console reporting
└── README.md     # Reviewer documentation and architecture specifications
```

Reviewer documentation for each workload:
- [`perf/fio/README.md`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/perf/fio/README.md)
- [`perf/concurrency/README.md`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/perf/concurrency/README.md)
- [`perf/sqlite/README.md`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/perf/sqlite/README.md)

---

## Evaluated Kernel Variants

Every benchmark workload runs against three distinct system configurations:
1. **`control` (Baseline)**: Upstream unmitigated Linux kernel on standard ext4 mounts.
2. **`off` (Mitigated Kernel, PKS Inactive)**: Evaluated kernel booted with `pcache_pks=off` on standard ext4, measuring baseline code path overhead without hardware key enforcement.
3. **`on` (Hardware PKS Active)**: Evaluated kernel booted with `pcache_pks=on` and the ext4 partition mounted with `-o pks_pagecache`.

---

## Output Architecture & Channel Separation

```
                             +-----------------------------------+
                             |             make perf             |
                             +-----------------+-----------------+
                                               |
                     +-------------------------+-------------------------+
                     |                                                   |
          Console Terminal Stream                             Persistent Data Stream
          (stdout via perf/run.sh)                               (strictly on disk)
                     |                                                   |
     +---------------+---------------+                   +---------------+---------------+
     |               |               |                   |               |               |
  Header          Live Log        Footer            Transcripts       Dataset       Raw JSONs
 88-col banner  per-variant    Dual Tables     perf/raw-*.log    perf/result.csv  perf/fio/raw/
from perf/run.sh from run.sh   from run.sh     (serial output)    (sole axis log) (strictly fio)
```

1. **Terminal Console**: Driven entirely by [`perf/run.sh`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/perf/run.sh). An 88-column header opens the run, followed by per-variant live execution logs. The footer delivers dual summary tables:
   - **Table 1: Fio Latency & Allocation Cost Breakdown**: Warm vs. cold write latencies, allocation cost delta ($\text{Cold} - \text{Warm}$), 4 KiB IOPS, and 1 MiB read bandwidth.
   - **Table 2: High-Level Benchmark Comparison**: Direct side-by-side comparison across `control`, `off`, and `on` variants with calculated percentage overheads.
2. **Persistent Storage**: All structured test records are stored strictly in [`perf/result.csv`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/perf/result.csv). Historical summaries are synthesized to [`results/data/perf_summary.csv`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/results/data/perf_summary.csv). No intermediate `result.log` files are created.
3. **Raw Telemetry**: Virtual machine serial transcripts are captured in `perf/raw-control.log`, `perf/raw-off.log`, and `perf/raw-on.log`. Comprehensive multi-block-size JSON outputs are preserved strictly for `fio` under `perf/fio/raw/<variant>/`.

---

## Result CSV Schema

The primary output log [`perf/result.csv`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/perf/result.csv) follows this structure:

```csv
node,variant,verdict,details
fio,control,PASS,iops4k_warm_write=10488.0 lat4k_warm_write_us=95.34 lat4k_warm_read_us=58.03 lat4k_cold_write_us=76.75 alloc_overhead_us=-18.59 bw1m_seq_read_kbs=81245.0
concurrency,control,PASS,bw_1t_mbps=42.1 bw_2t_mbps=82.4 bw_4t_mbps=158.2 scaling_pct=93.9
sqlite,control,PASS,tps_syncoff=428.59 tps_syncfull=4.41 lat_syncoff_us=2333.23 lat_syncfull_us=226757.37
fio,off,PASS,iops4k_warm_write=17176.0 lat4k_warm_write_us=58.22 lat4k_warm_read_us=43.12 lat4k_cold_write_us=76.54 alloc_overhead_us=18.32 bw1m_seq_read_kbs=79341.0
concurrency,off,PASS,bw_1t_mbps=43.0 bw_2t_mbps=83.1 bw_4t_mbps=159.0 scaling_pct=92.4
sqlite,off,PASS,tps_syncoff=410.54 tps_syncfull=4.5 lat_syncoff_us=2435.81 lat_syncfull_us=222222.22
fio,on,PASS,iops4k_warm_write=4013.0 lat4k_warm_write_us=249.18 lat4k_warm_read_us=44.84 lat4k_cold_write_us=221.12 alloc_overhead_us=-28.06 bw1m_seq_read_kbs=79341.0
concurrency,on,PASS,bw_1t_mbps=16.8 bw_2t_mbps=32.9 bw_4t_mbps=63.2 scaling_pct=94.0
sqlite,on,PASS,tps_syncoff=219.0 tps_syncfull=4.68 lat_syncoff_us=4566.21 lat_syncfull_us=213675.21
perf,all,PASS,completed=9_failed=0
```
