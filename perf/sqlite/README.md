# SQLite Rollback-Journal Macrobenchmark

## Upstream Origin & Purpose
- **Tool**: Embedded database engine (`sqlite3`), rollback journal transaction mode (`PRAGMA journal_mode=DELETE`).
- **Role in Thesis**: Evaluates real-world application macrobenchmark overheads where ACID database transactions trigger continuous sequences of page-cache writes, journal truncations, and directory metadata updates.

---

## Directory Layout
Raw intermediate JSON outputs are purged upon metric extraction; all extracted transactions-per-second (TPS) and latency metrics are logged directly to [`perf/result.csv`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/perf/result.csv):
```text
perf/sqlite/
├── run.sh             # Benchmark execution and telemetry extraction
├── sqlite_bench.sh    # Transaction generator and timing worker
└── README.md          # Reviewer documentation and metric specifications
```

---

## Applied Patches & Policy Compliance
- **Applied Patches**: None.
- **Verification**: The benchmark invokes the standard Debian distribution package `sqlite3` without custom binary patches or in-tree source modifications.

---

## Benchmark Workload Design

### Rollback-Journal Mechanics
SQLite operates with memory mapping disabled (`PRAGMA mmap_size=0`) and classic file-backed rollback journals. Each discrete transaction executes:
1. Creation and write of the rollback journal (`*-journal`) storing original page contents.
2. Modification of the main database file pages in the kernel page cache.
3. Commit sequence: truncating or removing the journal file to finalize the transaction.

### Evaluation Modes
1. **`synchronous=FULL` (500 transactions)**:
   - Issues an `fsync()` barrier on both the journal and database files at every commit boundary.
   - Storage-bound baseline: demonstrates that under physical disk flush latency, PKS kernel mitigation overhead is negligible.
2. **`synchronous=OFF` (5,000 transactions)**:
   - Completely disables disk flushes; all writes and journal operations remain purely inside the kernel page cache.
   - CPU-bound page-cache stress test: isolates the cumulative CPU cost of supervisor key permission switching across high-frequency write and truncate syscalls.

---

## Output Contract & Telemetry
Intermediate JSON results are generated in `/tmp` during execution and purged upon completion. The runner emits a single structured status line:
```text
STATUS node=sqlite variant=<control|off|on> verdict=PASS tps_syncoff=<tps> tps_syncfull=<tps> lat_syncoff_us=<lat> lat_syncfull_us=<lat>
```

Field descriptions:
- `tps_syncoff`: Transaction throughput with `synchronous=OFF` (Tx/s).
- `tps_syncfull`: Transaction throughput with `synchronous=FULL` (Tx/s).
- `lat_syncoff_us`: Mean per-transaction latency with `synchronous=OFF` in microseconds.
- `lat_syncfull_us`: Mean per-transaction latency with `synchronous=FULL` in microseconds.
