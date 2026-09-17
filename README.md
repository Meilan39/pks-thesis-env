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
│   ├── fsx/                # File System Exerciser (stress tests read/write/truncate/mmap)
│   │   ├── fsx.c
│   │   ├── Makefile
│   │   └── run_fsx.sh
│   ├── pjdfstest/          # POSIX filesystem compliance test suite
│   ├── exploit/
│   │   ├── copy-fail/      # Copy Fail (CVE-2026-31431) exploit
│   │   ├── dirty-frag/     # Dirty Frag (CVE-2026-43284, CVE-2026-43500) exploit
│   │   └── run_tests.sh    # Security validation harness (A/B testing)
│   └── benchmark/
│       └── run_benchmarks.sh # Benchmark suite placeholder (pending redesign)
├── scripts/
│   ├── common.sh           # Unified minimal logging utilities & pre-flight checks
│   ├── build_sec.sh        # Compiles debug-enabled security kernel (pcache_pks)
│   ├── build_perf.sh       # Compiles optimized mitigated performance kernel
│   ├── build_control.sh    # Compiles baseline upstream control kernel
│   ├── provision_disk.sh   # Provisions dual-partition ext4 disk image (Debian)
│   ├── update_disk.sh      # Synchronizes guest-assets into existing disk image
│   ├── fetch_results.sh    # Extracts artifacts from disk image to host results/
│   ├── analyze_bench.py    # Benchmark analysis placeholder (pending redesign)
│   ├── run_qemu_sec.sh     # QEMU launcher for security tests (batch / interactive)
│   ├── run_qemu_perf.sh    # QEMU launcher for mitigated performance kernel
│   └── run_qemu_control.sh # QEMU launcher for baseline control kernel
├── results/                # Host-side captured serial logs and extracted data
└── Makefile                # Pipeline automation entry point
```

---

## Quick Reference: `make help`

Run `make help` to inspect all available targets:

| Category | Command | Description |
| :--- | :--- | :--- |
| **Primary Workflow** | `make build` | Build all kernels and prepare disk image (tmux supported) |
| | `make test` | Run compliance & functional integrity suite (single QEMU boot) |
| | `make test-sec` | Execute end-to-end exploit validation (vulnerable vs mitigated) |
| | `make bench` | Micro-benchmark suite (under redesign) |
| **Granular Build** | `make build-sec` | Compile security kernel (`pcache_pks` diagnostics) |
| | `make build-perf` | Compile mitigated performance kernel |
| | `make build-control` | Compile baseline upstream control kernel |
| | `make build-all` | Synchronously compile all three kernels |
| **Disk Image** | `make provision-disk` | Bootstrap fresh 8GB Debian raw disk image |
| | `make update-disk` | Synchronize guest assets & autorun into image |
| **Granular Security** | `make test-sec-off` | Automated headless exploit run with `pcache_pks=off` (vulnerable) |
| | `make test-sec-on` | Automated headless exploit run with `pcache_pks=on` (mitigated) |
| | `make test-sec-copyfail` | Run Copy Fail exploit independently (A/B test) |
| | `make test-sec-dirtyfrag`| Run Dirty Frag exploit independently (A/B test) |
| | `make analyze-sec` | Parse serial logs and display verification report |
| **Granular Compliance** | `make test-fsx-off` | Run fsx exerciser with `pcache_pks=off` (vanilla ext4 baseline) |
| | `make test-fsx-on` | Run fsx exerciser with `pcache_pks=on` (protected mount validation) |
| | `make test-fsx` | Run both off/on fsx tests and summarize results |
| | `make test-pks-unit` | Run low-level in-kernel PKS self-test (`/sys/kernel/debug/x86/run_pks`) |
| **Interactive** | `make run-sec-off` | Interactive console with `pcache_pks=off` |
| | `make run-sec-on` | Interactive console with `pcache_pks=on` |
| | `make run-perf` | Interactive console for mitigated kernel |
| | `make run-control` | Interactive console for control kernel |
| **Housekeeping** | `make check-deps` | Verify host prerequisites and tools |
| | `make fetch-results` | Extract JSONs and logs from VM disk to host |
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
1. If `tmux` is available on the host, automatically launches or attaches to a detached background session (`pks-build`) so long compilations survive disconnects.
2. Sequentially compiles the security kernel (`build_sec`), mitigated performance kernel (`build_perf`), and control kernel (`build_control`).
3. If an existing `images/disk.img` is present, synchronizes assets via `update_disk.sh`. If absent, provisions a fresh Debian disk via `provision_disk.sh`.
4. Saves all build output to `results/build.log`.

### 2. Single-Boot Compliance & Functional Integrity (`make test`)

Executing `make test`:
1. Boots the mitigated kernel once with `pcache_pks=on` and `pks_auto=compliance`.
2. Sequentially executes in-kernel PKS driver self-tests, the `fsx` filesystem exerciser (5K rootfs operations, 10K protected mount operations, Commit 06 rejection test), and POSIX test suites.
3. Suppresses QEMU boot noise during execution, logs clean test output to `results/compliance.log`, and prints a unified pass/fail summary table on the host.

### 3. Automated Security Validation (`make test-sec`)

Executing `make test-sec` runs both test phases in batch mode:
1. Boots the security kernel with `pcache_pks=off` and `pks_auto=sec`. Executes Copy Fail and Dirty Frag, verifying that both exploits modify target file contents.
2. Boots the security kernel with `pcache_pks=on` and `pks_auto=sec`. Executes Copy Fail (trapped by PKS, task killed with SIGSEGV) followed by Dirty Frag (trapped by PKS in softirq, immediate kernel panic).
3. Invokes `analyze_sec.py` to parse `results/sec_off.log` and `results/sec_on.log`, displaying a side-by-side verification report.

### 4. Interactive Debugging

To manually explore the guest environment or run custom experiments:
```bash
make run-sec-on
```
The VM boots directly to a serial login prompt (`testuser` / `testuser`, or root passwordless sudo).
