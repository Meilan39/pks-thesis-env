# PKS Page-Cache Protection Evaluation Testbed (`pks-thesis-env`)

This repository provides an automated test harness, disk provisioning pipeline, and QEMU orchestration environment for evaluating Supervisor Protection Keys (PKS) page-cache isolation in the Linux kernel (`v5.18-rc3`).

The entire workflow is controllable from the top-level `Makefile`, featuring headless batch execution, automatic result harvesting, interactive debugging consoles, and unified logging.

---

## Directory Layout

```
pks-thesis-env/
├── config.mk               # Centralized configuration overrides (paths, RAM, SMP, etc.)
├── guest-assets/
│   ├── autorun/            # Headless automated execution service (systemd)
│   │   ├── pks-autorun.sh
│   │   └── pks-autorun.service
│   ├── unit-tests/         # In-kernel built-in PKS self-tests (debugfs)
│   │   └── run_pks_unit.sh
│   ├── exploit/
│   │   ├── copy-fail/      # Copy Fail (CVE-2026-31431) exploit
│   │   ├── dirty-frag/     # Dirty Frag (CVE-2026-43284, CVE-2026-43500) exploit
│   │   └── run_tests.sh    # Security validation harness (A/B testing)
│   └── benchmark/
│       └── run_benchmarks.sh # Synchronous buffered fio scaling benchmark suite
├── scripts/
│   ├── common.sh           # Unified minimal logging utilities & pre-flight checks
│   ├── build_sec.sh        # Compiles debug-enabled security kernel (pcache_pks)
│   ├── build_perf.sh       # Compiles optimized mitigated performance kernel
│   ├── build_control.sh    # Compiles baseline upstream control kernel
│   ├── provision_disk.sh   # Provisions dual-partition ext4 disk image (Debian)
│   ├── update_disk.sh      # Synchronizes guest-assets into existing disk image
│   ├── fetch_results.sh    # Extracts artifacts from disk image to host results/
│   ├── analyze_bench.py    # Generates thesis-ready comparison tables & overhead
│   ├── run_qemu_sec.sh     # QEMU launcher for security tests (batch / interactive)
│   ├── run_qemu_perf.sh    # QEMU launcher for mitigated benchmarks
│   └── run_qemu_control.sh # QEMU launcher for baseline benchmarks
├── results/                # Host-side captured serial logs and extracted data
└── Makefile                # Pipeline automation entry point
```

---

## Quick Reference: `make help`

Run `make help` to inspect all available targets:

| Category | Command | Description |
| :--- | :--- | :--- |
| **Kernel Build** | `make build-sec` | Compile security kernel (`pcache_pks` diagnostics) |
| | `make build-perf` | Compile mitigated performance kernel |
| | `make build-control` | Compile baseline upstream control kernel |
| | `make build-all` | Compile all three kernel configurations |
| **Disk Image** | `make provision-disk` | Bootstrap fresh 8GB Debian raw disk image |
| | `make update-disk` | Synchronize guest assets & autorun into image |
| **Batch Security** | `make test-pks-unit` | Automated in-kernel PKS unit tests (`/sys/kernel/debug/x86/run_pks`) |
| | `make test-sec-off` | Automated headless run with `pcache_pks=off` |
| | `make test-sec-on` | Automated headless run with `pcache_pks=on` |
| | `make test-sec` | Run both off/on tests sequentially & summarize |
| **Batch Benchmarks**| `make bench-control` | Headless fio benchmark on vanilla control kernel |
| | `make bench-mitigated`| Headless fio benchmark on mitigated kernel |
| | `make bench-all` | Run control + mitigated runs and analyze |
| **Analysis** | `make fetch-results` | Extract JSONs and logs from VM disk to host |
| | `make analyze-bench` | Parse fio JSONs and print overhead table |
| **Interactive** | `make run-sec-off` | Interactive console with `pcache_pks=off` |
| | `make run-sec-on` | Interactive console with `pcache_pks=on` |
| | `make run-perf` | Interactive console for mitigated kernel |
| | `make run-control` | Interactive console for control kernel |
| **Housekeeping** | `make check-deps` | Verify host prerequisites and tools |
| | `make clean-results` | Clear host results directory |
| | `make clean-all` | Clear results and disk image container |

---

## Configuration (`config.mk`)

All parameters are centralized in `config.mk` and can be overridden via environment variables or CLI arguments:

```makefile
# Override kernel source tree path
make build-sec DEV_KERNEL_DIR=/path/to/linux-5.18-rc3

# Override CPU cores and RAM allocation
make test-sec-on SMP=8 MEM_SEC=8G

# Pin benchmark execution to dedicated host cores
make bench-all TASKSET_CPUS="4-7"
```

---

## Evaluation Workflows

### 1. Automated Security Validation (`make test-sec`)

Executing `make test-sec` automatically runs both test phases in batch mode:
1. Boots the security kernel with `pcache_pks=off` and `pks_auto=sec`.
2. The in-guest autorun service executes `/exploit/run_tests.sh`, logs results, and powers off.
3. Boots the security kernel with `pcache_pks=on` and `pks_auto=sec`.
4. Executes the tests against PKS-protected storage, detects supervisor `#PF` events, logs results, and powers off.
5. Displays an A/B delta summary verifying that exploits succeeded in the off state and were neutralized in the on state.

### 2. Automated Micro-benchmarking (`make bench-all`)

Executing `make bench-all`:
1. Boots the control kernel in batch mode (`pks_auto=bench`), executes the synchronous buffered write scaling and 4KB random read suites, and powers off.
2. Extracts control benchmark JSONs into `results/extracted/bench/control/`.
3. Boots the mitigated kernel in batch mode (`pcache_pks=on`), runs the identical benchmark suite, and powers off.
4. Extracts mitigated benchmark JSONs into `results/extracted/bench/mitigated/`.
5. Invokes `analyze_bench.py` to print a Markdown table with mean throughput (MB/s), IOPS, latency, and throughput overhead percentage.

### 3. Interactive Debugging

To manually explore the guest environment or run custom experiments:
```bash
make run-sec-on
```
The VM boots directly to a serial login prompt (`testuser` / `testuser`, or root passwordless sudo).
