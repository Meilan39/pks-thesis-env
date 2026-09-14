# PKS Page-Cache Protection Evaluation Testbed (`pks-thesis-env`)

This repository provides an automated test harness, disk provisioning pipeline, and QEMU orchestration environment for evaluating Supervisor Protection Keys (PKS) page-cache isolation in the Linux kernel (`v5.18-rc3`).

---

## Directory Layout

```
pks-thesis-env/
├── guest-assets/
│   ├── exploit/
│   │   ├── copy-fail/      # Copy Fail (CVE-2026-31431) headless exploit
│   │   ├── dirty-frag/     # Dirty Frag (CVE-2026-43284, CVE-2026-43500) headless exploit
│   │   └── run_tests.sh    # Automated security validation harness
│   └── benchmark/
│       └── run_benchmarks.sh # Automated fio buffered I/O scaling benchmark suite
├── scripts/
│   ├── build_sec.sh        # Compiles debug-enabled security kernel (pcache_pks)
│   ├── build_perf.sh       # Compiles optimized mitigated performance kernel
│   ├── build_control.sh    # Compiles vanilla upstream control baseline
│   ├── provision_disk.sh   # Provisions dual-partition raw ext4 disk image (Debian)
│   ├── update_disk.sh      # Incremental sync of guest-assets into disk image
│   ├── run_qemu_sec.sh     # QEMU launcher for security causality validation (off/on)
│   ├── run_qemu_perf.sh    # QEMU launcher for mitigated performance benchmarks
│   └── run_qemu_control.sh # QEMU launcher for control baseline benchmarks
└── Makefile                # Pipeline automation entry point
```

---

## Quick Start

### 1. Build Kernels

```bash
# Build the security kernel with PKS enabled and debug diagnostics
make build-sec

# Build the performance benchmarking kernels
make build-perf
make build-control
```

### 2. Provision the Disk Image

The provisioning script creates a raw 8GB image partitioned into:
* Partition 1 (`/dev/vda1`, 6GB): Debian Bookworm root filesystem (`/`).
* Partition 2 (`/dev/vda2`, 2GB): Dedicated ext4 partition mounted at `/mnt/protected`.

```bash
make provision-image
```

If guest-assets are modified, sync them into the disk without re-provisioning:
```bash
make update-disk
```

---

## Evaluation Workflow

### A. Security Causality Validation (A/B Testing)

#### 1. Baseline Test (Vulnerable / PKS Disabled)
Boot with PKS disabled:
```bash
make run-sec-off
```
Inside the guest VM:
```bash
sudo /exploit/run_tests.sh
```
* **Expected Result**: Both `copy-fail` and `dirty-frag` report `SUCCEEDED` (target file checksum altered in page cache).

#### 2. Mitigated Test (PKS Active)
Boot with PKS enabled:
```bash
make run-sec-on
```
Inside the guest VM:
```bash
sudo /exploit/run_tests.sh
```
* **Expected Result**: Both exploits are `BLOCKED` (page cache protected, file checksum unchanged, supervisor `#PF` trace logged in `dmesg`).

---

### B. Performance Micro-benchmarking (`fio`)

#### 1. Control Baseline Run
Boot the vanilla kernel (usable memory equalized to 3840MB, taskset CPU core pinning):
```bash
TASKSET_CPUS="2-5" make run-control
```
Inside the guest VM:
```bash
sudo /benchmark/run_benchmarks.sh
```

#### 2. Mitigated Run
Boot the PKS-mitigated kernel (4096MB RAM total, 256MB static pool reserved = 3840MB usable):
```bash
TASKSET_CPUS="2-5" make run-perf
```
Inside the guest VM:
```bash
sudo /benchmark/run_benchmarks.sh
```

Benchmark output JSON files are saved to `/tmp/bench_results/` for latency and throughput comparison across block sizes (4KB to 1MB).
