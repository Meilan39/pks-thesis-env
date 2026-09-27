# PKS Page-Cache Protection Evaluation Testbed (`pks-thesis-env`)

This repository provides a modular, reproducible evaluation testbed for Supervisor Protection Keys (PKS) page-cache isolation in the Linux kernel (`v5.18-rc3`).

The workflow is orchestrated from the top-level [Makefile](file:///Users/meilan/Documents/大学/3年前期/研究/卒論/pks-thesis-env/Makefile), featuring headless batch execution, direct 9p workspace mounting, automatic result harvesting, interactive debugging consoles, unified logging with `tee`, and decoupled publication figure generation.

---

## Directory Layout

```text
pks-thesis-env/
├── Makefile                        # Unified command orchestrator matching environment-2.tex
├── config.mk                       # Static paths, VM memory sizing, and CPU allocation
│
├── tests/                          # Unit and compliance validation workloads
│   ├── Makefile                    # Sub-directory aggregator (make all, make clean)
│   ├── pks-unit/                   # Upstream x86 PKS architectural selftest
│   ├── sanity/                     # PKS page-cache scoping & debugfs integrity test
│   ├── fsx/                        # Filesystem exerciser stress harness (10K ops)
│   └── pjd/                        # POSIX filesystem compliance test suite
│
├── sec/                            # Security vulnerability exploit harnesses
│   ├── Makefile                    # Sub-directory aggregator (make all, make clean)
│   ├── copy-fail/                  # CVE-2026-31431 exploit harness (AF_ALG splice)
│   ├── dirty-frag/                 # CVE-2026-43284 exploit harness (IPv4 fragment assembly)
│   └── fragnesia/                  # CVE-2026-46300 exploit harness (IPSec ESPINTCP)
│
├── perf/                           # Performance evaluation benchmarks
│   ├── Makefile                    # Sub-directory aggregator (make all, make clean)
│   ├── fio/                        # Micro-benchmark: block-size latency/throughput sweeps
│   ├── concurrency/                # Micro-benchmark: multithreaded scalability sweeps
│   └── sqlite/                     # Macro-benchmark: transactional database workload
│
├── scripts/                        # Lean, single-purpose host automation scripts
│   ├── common.sh                   # Shared console formatting and status print helpers
│   ├── compile-all.sh              # Single loop calling 'make all' across tests/, sec/, perf/
│   ├── clean-all.sh                # Single loop calling 'make clean' across tests/, sec/, perf/
│   ├── build/                      # Kernel build automation (sec, perf, control)
│   ├── disk/                       # Virtual disk lifecycle (provision, update, compile)
│   ├── run/                        # Virtual machine runners and test dispatchers
│   ├── data/                       # Telemetry extraction and report synthesis
│   └── guest-autorun/              # Headless in-guest systemd autorun service
│
├── results/                        # Clean, structured evaluation artifacts
│   ├── build.log                   # Full log for make build
│   ├── test.log                    # Full log for make test
│   ├── sec.log                     # Full log for make sec
│   ├── perf.log                    # Full log for make perf
│   ├── raw/                        # Granular per-target execution logs and JSONs
│   └── data/                       # Canonical summarized deliverables
│       ├── test_summary.csv        # Compliance and sanity test verdict summary
│       ├── sec_summary.csv         # Neutralization verdict matrix across all 3 exploits
│       └── perf_summary.csv        # Normalized tidy metrics dataset for all sweeps
│
└── tools/                          # Decoupled offline analysis and publication graphics
    └── plotting/
        ├── Makefile                # Standalone figure rendering makefile
        ├── plot_thesis_figures.py  # Generates Figures 1-5 and Table 1 TOST
        ├── requirements.txt        # Python dependencies (matplotlib, pandas, scipy)
        └── figures/                # Output PDF and PNG vector graphics
```

---

## Quick Reference: `make help`

Run `make help` to inspect all available targets:

| Category | Command | Description |
| :--- | :--- | :--- |
| **Primary Workflow** | `make build` | Compile kernels, provision disk, compile test harnesses |
| | `make test` | Execute compliance & integrity test suite (off & on) |
| | `make sec` | Execute 3-way exploit neutralization evaluation |
| | `make perf` | Execute full A/B performance benchmark sweeps |
| **Granular Build** | `make build-sec` | Compile security diagnostic kernel |
| | `make build-perf` | Compile performance mitigated kernel |
| | `make build-control` | Compile baseline pristine upstream Linux v5.18-rc3 |
| | `make disk-provision`| Bootstrap Debian Bookworm and partition `images/disk.img` |
| | `make disk-update` | Synchronize `/pks-thesis-env` into virtual disk image |
| | `make compile` | Compile all in-guest evaluation binaries |
| | `make run-qemu` | Launch interactive serial debugging console |
| | `make end-qemu` | Terminate all active QEMU instances |
| **Granular Compliance** | `make pks-unit-[off\|on]` | Architectural MSR/CPUID PKS unit selftest |
| | `make sanity-[off\|on]` | PKS page-cache scoping & debugfs test |
| | `make fsx-[off\|on]` | Filesystem exerciser (10,000 random operations) |
| | `make pjd-[off\|on]` | POSIX filesystem compliance suite |
| | `make test-[off\|on]` | Consolidated single-boot compliance suite |
| | `make analyze-test` | Synthesize compliance evaluation report (`results/data/test_summary.csv`) |
| **Granular Security** | `make copy-fail-[off\|on]` | CVE-2026-31431 AF_ALG splice exploit |
| | `make dirty-frag-[off\|on]` | CVE-2026-43284 IPv4 fragment reassembly exploit |
| | `make fragnesia-[off\|on]` | CVE-2026-46300 IPSec ESPINTCP workqueue exploit |
| | `make sec-[off\|on]` | Execute all 3 exploit vectors under specified mode |
| | `make analyze-sec` | Synthesize 3-way exploit neutralization matrix (`results/data/sec_summary.csv`) |
| **Benchmarking** | `make fio-[control\|off\|on]-[warm\|cold]` | Amortized block sweep (512B - 1MB) |
| | `make concurrency-[control\|off\|on]` | Multithreaded scaling (1, 2, 4 threads) |
| | `make sqlite-[control\|off\|on]` | SQLite rollback journal macrobenchmark |
| | `make perf-[control\|off\|on]` | Execute complete benchmark suite on specified variant |
| | `make analyze-perf` | Synthesize normalized A/B performance summary (`results/data/perf_summary.csv`) |
| **Housekeeping** | `make clean` | Remove compiled test binaries across `tests/`, `sec/`, `perf/` |
| | `make clean-results` | Remove execution logs and generated CSV datasets |
| | `make clean-image` | Remove `images/disk.img` container |
| | `make clean-build` | Remove compiled kernel bzImage binaries |
| | `make clean-all` | Reset workspace to pristine pre-build state |

---

## Decoupled Offline Plotting

Figure and table generation is completely decoupled from the testbed evaluation environment. It consumes `results/data/perf_summary.csv` purely as input data:

```bash
cd tools/plotting
make deps       # Install pandas, matplotlib, scipy
make all        # Generate Figures 1-5 and Table 1 (TOST)
```

Generated publication artifacts are placed into `tools/plotting/figures/`:
- `fig1_warm_latency_sweep.pdf` & `.png`
- `fig2_cold_latency_sweep.pdf` & `.png`
- `fig3_throughput_comparison.pdf` & `.png`
- `fig4_concurrency_scaling.pdf` & `.png`
- `fig5_sqlite_macrobenchmark.pdf` & `.png`
- `table1_tost_equivalence.tex`
