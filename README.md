# PKS Page-Cache Protection Evaluation Testbed (`pks-thesis-env`)

This repository provides an automated test harness, disk provisioning pipeline, and QEMU orchestration environment for evaluating Supervisor Protection Keys (PKS) page-cache isolation in the Linux kernel (`v5.18-rc3`).

The entire workflow is controllable from the top-level `Makefile`, featuring headless batch execution, automatic result harvesting, interactive debugging consoles, unified logging, publication figure generation, and statistical equivalence testing.

---

## Directory Layout

```
pks-thesis-env/
├── config.mk               # Centralized configuration overrides (paths, RAM, SMP, etc.)
├── guest-assets/
│   ├── autorun/            # Headless automated execution service (systemd)
│   │   ├── pks-autorun.sh
│   │   └── pks-autorun.service
│   ├── unit-tests/         # In-kernel PKS tests and userspace VFS sanity suite
│   │   ├── pks_sanity_test.c # Asserts scope counting, static pool PFNs, and fail-closed policies
│   │   ├── Makefile
│   │   └── run_pks_unit.sh
│   ├── fsx/                # File System Exerciser (stress tests read/write/truncate/mmap)
│   │   ├── fsx.c
│   │   ├── Makefile
│   │   └── run_fsx.sh
│   ├── pjdfstest/          # POSIX filesystem compliance test suite
│   ├── exploit/
│   │   ├── copy-fail/      # Copy Fail (CVE-2026-31431) exploit
│   │   ├── dirty-frag/     # Dirty Frag (CVE-2026-43284, CVE-2026-43500) exploit
│   │   ├── fragnesia/      # Fragnesia (CVE-2026-46300) XFRM ESPINTCP exploit
│   │   └── run_tests.sh    # Security validation harness (A/B testing)
│   └── benchmark/
│       ├── fio_sweep.job   # Standardized synchronous fio job specification
│       ├── sqlite_bench.sh # SQLite rollback journal macrobenchmark (FULL vs OFF)
│       └── run_benchmarks.sh # Multi-phase benchmark orchestrator (warm/cold fio, concurrency, SQLite)
├── scripts/
│   ├── common.sh           # Unified logging utilities and pre-flight checks
│   ├── build_sec.sh        # Compiles debug-enabled security kernel (pcache_pks + ESPINTCP / crypto)
│   ├── build_perf.sh       # Compiles optimized mitigated performance kernel (zero debug overhead)
│   ├── build_control.sh    # Compiles baseline upstream control kernel
│   ├── build_all.sh        # Background tmux compilation orchestrator for all kernels
│   ├── provision_disk.sh   # Provisions dual-partition ext4 Debian disk image
│   ├── update_disk.sh      # Synchronizes guest-assets into disk image and compiles in chroot
│   ├── fetch_results.sh    # Extracts artifacts and raw JSONs from disk image to host results/
│   ├── parse_results.py    # Aggregates raw fio and SQLite JSONs into canonical tidy CSV
│   ├── analyze_bench.py    # Benchmark analysis and statistical summary utilities
│   ├── analyze_sec.py      # Parses exploit logs and generates 3-way exploit neutralization matrix
│   ├── run_qemu_sec.sh     # QEMU launcher for security tests (batch and interactive)
│   ├── run_qemu_perf.sh    # QEMU launcher for mitigated performance kernel
│   ├── run_qemu_control.sh # QEMU launcher for baseline control kernel
│   └── run_compliance.sh   # Single-boot compliance and functional integrity runner
├── tools/
│   └── plotting/
│       ├── plot_thesis_figures.py # Publication-quality vector figures (Figures 1–5, Table 1 TOST)
│       └── requirements.txt       # Python dependencies (pandas, matplotlib, scipy)
├── results/                # Host-side captured serial logs and extracted data
│   ├── raw/                # Extracted in-guest JSONs and system provenance metadata
│   └── processed/          # Canonical benchmark_summary.csv and rendered figures
└── Makefile                # Pipeline automation entry point
```

---

## Quick Reference: `make help`

Run `make help` to inspect all available targets:

| Category | Command | Description |
| :--- | :--- | :--- |
| **Primary Workflow** | `make build` | Build all kernels and prepare disk image with tmux session support |
| | `make test` | Run compliance and functional integrity suite in a single QEMU boot |
| | `make test-sec` | Execute end-to-end exploit validation across Copy Fail, Dirty Frag, and Fragnesia |
| | `make bench` | Execute complete A/B benchmark suite across control and mitigated kernels |
| | `make parse-results` | Process raw fio and SQLite JSONs into canonical `benchmark_summary.csv` |
| | `make plot-bench` | Render thesis publication vector figures and TOST statistical equivalence tables |
| **Granular Build** | `make build-sec` | Compile security kernel with `pcache_pks` diagnostics and ESPINTCP support |
| | `make build-perf` | Compile mitigated performance kernel with zero diagnostic overhead |
| | `make build-control` | Compile baseline upstream control kernel |
| | `make build-all` | Synchronously compile all three kernel configurations |
| **Disk Image** | `make provision-disk` | Bootstrap fresh 8GB Debian raw disk image |
| | `make update-disk` | Synchronize guest assets and recompile harnesses in chroot |
| **Granular Security** | `make test-sec-off` | Automated exploit run with `pcache_pks=off` (vulnerable baseline) |
| | `make test-sec-on` | Automated exploit run with `pcache_pks=on` (mitigated) |
| | `make test-sec-copyfail` | Run Copy Fail exploit independently with dedicated off and on boots |
| | `make test-sec-dirtyfrag`| Run Dirty Frag exploit independently with dedicated off and on boots |
| | `make test-sec-fragnesia`| Run Fragnesia exploit independently with dedicated off and on boots |
| | `make analyze-sec` | Parse exploit serial logs and display 3-way neutralization report |
| **Granular Compliance** | `make test-fsx-off` | Run fsx exerciser with `pcache_pks=off` (vanilla ext4 baseline) |
| | `make test-fsx-on` | Run fsx exerciser with `pcache_pks=on` (protected mount validation) |
| | `make test-fsx` | Run both off and on fsx tests and summarize results |
| | `make test-pks-unit` | Run low-level in-kernel PKS self-test via DebugFS |
| **Benchmarking** | `make bench-control` | Run baseline control benchmark VM in batch mode |
| | `make bench-mitigated`| Run mitigated benchmark VM with `pcache_pks=on` in batch mode |
| | `make bench-off` | Run mitigated benchmark VM with `pcache_pks=off` for ablation in batch mode |
| **Interactive Shells** | `make run-sec-off` | Interactive serial console with `pcache_pks=off` |
| | `make run-sec-on` | Interactive serial console with `pcache_pks=on` |
| | `make run-perf` | Interactive serial console for mitigated performance kernel |
| | `make run-control` | Interactive serial console for baseline control kernel |
| **Housekeeping** | `make check-deps` | Verify host prerequisites and required packages |
| | `make fetch-results` | Extract JSONs and logs from VM disk image to host |
| | `make clean-results` | Clear host results directory |
| | `make clean-all` | Clear results and disk image container |

---

## Configuration (`config.mk`)

All parameters are centralized in `config.mk` and can be overridden via environment variables or CLI arguments:

```makefile
# Override kernel source tree path
make build-sec DEV_KERNEL_DIR=/path/to/linux-pks-thesis
make build-control CONTROL_KERNEL_DIR=/path/to/linux-pks-thesis-control

# Override CPU cores and RAM allocation
make test-sec SMP=8 MEM_SEC=8G

# Force disk re-provisioning during build
make build FORCE_REPROVISION=1
```

---

## Evaluation Workflows

### 1. Autonomous Build Pipeline (`make build`)

Executing `make build`:
1. If `tmux` is available on the host, automatically launches or attaches to a detached background session (`pks-build`) so long compilations survive terminal disconnects.
2. Sequentially compiles the security kernel (`build_sec`), mitigated performance kernel (`build_perf`), and control kernel (`build_control`).
3. If an existing `images/disk.img` is present, synchronizes assets and recompiles binaries in chroot via `update_disk.sh`. If absent, provisions a fresh Debian disk via `provision_disk.sh`.
4. Saves all build output to `results/build.log`.

### 2. Single-Boot Compliance & Functional Integrity (`make test`)

Executing `make test`:
1. Boots the mitigated kernel once with `pcache_pks=on` and `pks_auto=compliance`.
2. Sequentially executes in-kernel PKS driver self-tests, the userspace `pks_sanity_test` suite, the `fsx` filesystem exerciser (5K rootfs operations, 10K protected mount operations, Commit 06 rejection test), and POSIX compliance test suites.
3. The userspace sanity harness (`pks_sanity_test.c`) reads `/sys/kernel/debug/pcache_pks/status` to assert that write system calls increment scope entry and exit counters by exactly 1, read system calls trigger zero increments, static pool folios fall strictly within physical pool PFN boundaries via `/proc/self/pagemap`, and fail-closed system calls return `-EOPNOTSUPP`.
4. Suppresses early QEMU boot noise during execution, logs clean test output to `results/compliance.log`, and prints a unified summary table on the host.

### 3. Automated Security Validation (`make test-sec`)

Executing `make test-sec` runs dedicated QEMU boots for each exploit:
1. **Copy Fail (`make test-sec-copyfail`)**:
   * Evaluates process-context page cache corruption (CVE-2026-31431).
   * In `pcache_pks=off`, the exploit overwrites target page-cache contents.
   * In `pcache_pks=on`, hardware PKS intercepts the unauthorized store with `#PF (0x0023)` on Key 1, terminating the attacking task via process isolation (SIGSEGV) without destabilizing the operating system.
2. **Dirty Frag (`make test-sec-dirtyfrag`)**:
   * Evaluates softirq network defragmentation page cache corruption (CVE-2026-43284, CVE-2026-43500).
   * In `pcache_pks=off`, page-cache corruption succeeds in interrupt context.
   * In `pcache_pks=on`, the unauthorized write in softirq context triggers a hardware `#PF (0x0023)`, resulting in an immediate fail-closed kernel panic (`Fatal exception in interrupt`) that guarantees memory containment.
3. **Fragnesia (`make test-sec-fragnesia`)**:
   * Evaluates IPsec XFRM ESPINTCP TCP ULP page cache corruption (CVE-2026-46300).
   * In `pcache_pks=off`, splice and crypto transform operations modify target cache pages.
   * In `pcache_pks=on`, the crypto transform write is intercepted by Key 1 access restriction, triggering an immediate fail-closed panic in softirq context.
4. **Consolidated Analysis (`make analyze-sec`)**:
   * `scripts/analyze_sec.py` parses individual and monolithic logs, validating pre and post MD5 hashes, `#PF` error codes, and interrupt panic signatures to output a side-by-side 3-way neutralization report.

### 4. A/B Performance Benchmarking & Publication Pipeline (`make bench`)

Executing `make bench` orchestrates the complete experimental performance workflow:
1. **Control Run (`make bench-control`)**: Boots the baseline upstream kernel and executes the in-guest benchmark suite in batch mode, writing raw JSONs to `/mnt/protected/bench_results/raw/`.
2. **Mitigated Run (`make bench-mitigated`)**: Boots the performance kernel with `pcache_pks=on` and runs the identical suite.
3. **Multi-Phase Benchmark Workloads**:
   * **Phase 1 (Warm Sweep)**: Evaluates `write()`, `read()`, and `ftruncate()` across block sizes from 512 B to 1 MiB using standard fio (including `ioengine=ftruncate`) on warm cache pages.
   * **Phase 2 (Cold Sweep)**: Evaluates first-touch allocation across block sizes with cache dropping between iterations, isolating static pool allocation costs.
   * **Phase 3 (Concurrency Scaling)**: Evaluates multi-threaded throughput and lock contention across 1, 2, and 4 concurrent workers on thread-private files.
   * **Phase 4 (SQLite Macrobenchmark)**: Evaluates 5,000 real-world database transactions in rollback journal mode under `synchronous=FULL` and `synchronous=OFF`.
   * **Phase 5 (Provenance Logging)**: Captures CPU topology, kernel command line, mount options, memory footprint, and virtualization steal time.
4. **Host-Side Extraction & Parsing (`make parse-results`)**:
   * Extracts raw JSONs from the guest disk image via `scripts/fetch_results.sh`.
   * Ingests raw JSON data with `scripts/parse_results.py`, formatting metrics into canonical tidy CSV format (`results/processed/benchmark_summary.csv`).
5. **Publication Figure Generation (`make plot-bench`)**:
   * Executes `tools/plotting/plot_thesis_figures.py` to produce publication-grade vector graphics (PDF and PNG):
     - **Figure 1**: Multi-Syscall Amortization Curves (`write`, `read`, `ftruncate`).
     - **Figure 2**: Cold vs Warm Cache Scaling overhead deltas.
     - **Figure 3**: 3-Way Kernel Ablation Comparison (`baseline_control`, `mitigated_off`, `mitigated_on`).
     - **Figure 4**: Multi-Core Concurrency Scaling throughput and speedup.
     - **Figure 5**: SQLite Macrobenchmark TPS and Latency distributions.
     - **Table 1**: Two One-Sided Tests (TOST) statistical equivalence table demonstrating read-path parity within a 1% equivalence margin.

### 5. Interactive Debugging

To manually explore the guest environment, inspect DebugFS counters, or run custom experiments:
```bash
make run-sec-on
```
The VM boots directly to a serial login prompt (`testuser` / `testuser`, or passwordless sudo).
