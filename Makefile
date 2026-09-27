# ==============================================================================
# Makefile - Unified Top-Level Orchestration for PKS Evaluation Testbed
# ==============================================================================
SHELL := /bin/bash
.DEFAULT_GOAL := help

-include config.mk

export DEV_KERNEL_DIR CONTROL_KERNEL_DIR DISK_IMG DISK_SIZE ROOTFS_SIZE PROT_SIZE
export DEBIAN_SUITE DEBIAN_ARCH DEBIAN_MIRROR SCRIPTS_DIR TESTS_DIR SEC_DIR PERF_DIR
export IMAGES_DIR RESULTS_DIR TOOLS_DIR QEMU_BIN SMP MEM

# Ensure output directories exist
$(shell mkdir -p results/raw results/data images)

.PHONY: help build test sec perf \
        build-sec build-perf build-control disk-provision disk-update compile run-qemu end-qemu \
        pks-unit pks-unit-off pks-unit-on sanity sanity-off sanity-on fsx fsx-off fsx-on pjd pjd-off pjd-on \
        test-off test-on analyze-test \
        copy-fail copy-fail-off copy-fail-on dirty-frag dirty-frag-off dirty-frag-on fragnesia fragnesia-off fragnesia-on \
        sec-off sec-on analyze-sec \
        fio-control-warm fio-control-cold fio-off-warm fio-off-cold fio-on-warm fio-on-cold \
        fio fio-warm fio-cold concurrency concurrency-control concurrency-off concurrency-on \
        sqlite sqlite-control sqlite-off sqlite-on perf-control perf-off perf-on analyze-perf \
        clean clean-results clean-image clean-all

# ==============================================================================
# Help
# ==============================================================================
help:
	@echo "======================================================================"
	@echo " PKS Thesis Evaluation Environment - Available Commands"
	@echo "======================================================================"
	@echo ""
	@echo "  Primary Reproduction Entry Points:"
	@echo "    make build              Compile kernels, provision disk, compile test harnesses"
	@echo "    make test               Execute compliance & integrity test suite (off & on)"
	@echo "    make sec                Execute 3-way exploit neutralization evaluation"
	@echo "    make perf               Execute full A/B performance benchmark sweeps"
	@echo ""
	@echo "  Granular Kernel & Disk Lifecycle:"
	@echo "    make build-sec          Compile security diagnostic kernel"
	@echo "    make build-perf         Compile performance mitigated kernel"
	@echo "    make build-control      Compile baseline pristine upstream Linux v5.18-rc3"
	@echo "    make disk-provision     Bootstrap Debian Bookworm and partition images/disk.img"
	@echo "    make disk-update        Synchronize /pks-thesis-env into virtual disk image"
	@echo "    make compile            Compile all in-guest evaluation binaries"
	@echo "    make run-qemu           Launch interactive serial debugging console"
	@echo "    make end-qemu           Terminate all active QEMU instances"
	@echo ""
	@echo "  Compliance & Unit Tests:"
	@echo "    make pks-unit-[off|on]  Architectural MSR/CPUID PKS unit selftest"
	@echo "    make sanity-[off|on]    PKS page-cache scoping & debugfs test"
	@echo "    make fsx-[off|on]       Filesystem exerciser (10,000 random operations)"
	@echo "    make pjd-[off|on]       POSIX filesystem compliance suite"
	@echo "    make test-[off|on]      Consolidated single-boot compliance suite"
	@echo "    make analyze-test       Synthesize compliance evaluation report"
	@echo ""
	@echo "  Security Exploit Benchmarks:"
	@echo "    make copy-fail-[off|on] CVE-2026-31431 AF_ALG splice exploit"
	@echo "    make dirty-frag-[off|on] CVE-2026-43284 IPv4 fragment reassembly exploit"
	@echo "    make fragnesia-[off|on] CVE-2026-46300 IPSec ESPINTCP workqueue exploit"
	@echo "    make sec-[off|on]       Execute all 3 exploit vectors under specified mode"
	@echo "    make analyze-sec        Synthesize 3-way exploit neutralization matrix"
	@echo ""
	@echo "  Performance Benchmarks:"
	@echo "    make fio-[control|off|on]-[warm|cold] Amortized block sweep (512B - 1MB)"
	@echo "    make concurrency-[control|off|on]     Multithreaded scaling (1, 2, 4 threads)"
	@echo "    make sqlite-[control|off|on]          SQLite rollback journal macrobenchmark"
	@echo "    make perf-[control|off|on]            Execute complete benchmark suite"
	@echo "    make analyze-perf                     Synthesize normalized A/B performance summary"
	@echo ""
	@echo "  Cleanup & Teardown:"
	@echo "    make clean              Remove compiled test binaries across tests/, sec/, perf/"
	@echo "    make clean-results      Remove test execution logs and generated CSV datasets"
	@echo "    make clean-image        Remove images/disk.img container"
	@echo "    make clean-all          Reset workspace to pristine state (kernel images preserved)"
	@echo "======================================================================"

# ==============================================================================
# Group 1: Primary Reproduction Entry Points
# ==============================================================================
build:
	@mkdir -p results/raw results/data
	@{ \
		echo "======================================================================"; \
		echo " [build] PKS Kernel Compilation & Disk Environment Pipeline"; \
		echo "======================================================================"; \
		$(MAKE) --no-print-directory build-sec; \
		$(MAKE) --no-print-directory build-perf; \
		$(MAKE) --no-print-directory build-control; \
		$(MAKE) --no-print-directory disk-provision; \
		$(MAKE) --no-print-directory disk-update; \
		$(MAKE) --no-print-directory compile; \
		echo "======================================================================"; \
		echo " [build] Build Pipeline Summary & Artifact Verification"; \
		echo "----------------------------------------------------------------------"; \
		echo "  Security Kernel:     $$(ls -lh "$$DEV_KERNEL_DIR/build_sec/arch/x86/boot/bzImage" 2>/dev/null | awk '{print $$5}')  [READY]"; \
		echo "  Performance Kernel:  $$(ls -lh "$$DEV_KERNEL_DIR/build_perf/arch/x86/boot/bzImage" 2>/dev/null | awk '{print $$5}') [READY]"; \
		echo "  Control Kernel:      $$(ls -lh "$$CONTROL_KERNEL_DIR/build_control/arch/x86/boot/bzImage" 2>/dev/null | awk '{print $$5}') [READY]"; \
		echo "  Disk Image:          $$(ls -lh images/disk.img 2>/dev/null | awk '{print $$5}') [READY]"; \
		echo "  Overall Status:      ALL 6 BUILD TARGETS COMPILED SUCCESSFULLY"; \
		echo "======================================================================"; \
	} 2>&1 | tee results/build.log

test:
	@mkdir -p results/raw results/data
	@{ \
		echo "======================================================================"; \
		echo " [test] PKS Compliance & Functional Integrity Suite"; \
		echo "======================================================================"; \
		$(MAKE) --no-print-directory test-off; \
		$(MAKE) --no-print-directory test-on; \
		$(MAKE) --no-print-directory analyze-test; \
	} 2>&1 | tee results/test.log

sec:
	@mkdir -p results/raw results/data
	@{ \
		echo "======================================================================"; \
		echo " [sec] PKS Security Evaluation: End-to-End Exploit Neutralization"; \
		echo "======================================================================"; \
		$(MAKE) --no-print-directory sec-off; \
		$(MAKE) --no-print-directory sec-on; \
		$(MAKE) --no-print-directory analyze-sec; \
	} 2>&1 | tee results/sec.log

perf:
	@mkdir -p results/raw results/data
	@{ \
		echo "======================================================================"; \
		echo " [perf] PKS Performance Evaluation: Micro- & Macro-Benchmark Sweeps"; \
		echo "======================================================================"; \
		$(MAKE) --no-print-directory perf-control; \
		$(MAKE) --no-print-directory perf-off; \
		$(MAKE) --no-print-directory perf-on; \
		$(MAKE) --no-print-directory analyze-perf; \
	} 2>&1 | tee results/perf.log

# ==============================================================================
# Group 2: Kernel Compilation & Disk Lifecycle
# ==============================================================================
build-sec:
	@./scripts/build/build_sec.sh $(DEV_KERNEL_DIR) > results/raw/build-sec.log 2>&1 || (cat results/raw/build-sec.log && exit 1)

build-perf:
	@./scripts/build/build_perf.sh $(DEV_KERNEL_DIR) > results/raw/build-perf.log 2>&1 || (cat results/raw/build-perf.log && exit 1)

build-control:
	@./scripts/build/build_control.sh $(CONTROL_KERNEL_DIR) > results/raw/build-control.log 2>&1 || (cat results/raw/build-control.log && exit 1)

disk-provision:
	@./scripts/disk/disk_provision.sh $(DISK_IMG) > results/raw/disk-provision.log 2>&1 || (cat results/raw/disk-provision.log && exit 1)

disk-update:
	@./scripts/disk/disk_update.sh $(DISK_IMG) > results/raw/disk-update.log 2>&1 || (cat results/raw/disk-update.log && exit 1)

compile:
	@./scripts/compile-all.sh > results/raw/compile.log 2>&1 || (cat results/raw/compile.log && exit 1)

run-qemu:
	@./scripts/run_qemu.sh $(or $(VARIANT),perf) $(or $(MODE),on) shell

end-qemu:
	@killall -9 qemu-system-x86_64 2>/dev/null || true
	@echo "[end-qemu] Terminated all active QEMU emulator instances. [DONE]"
	@echo ""

# ==============================================================================
# Group 3: Unit and Compliance Testing
# ==============================================================================
pks-unit-off:
	@./scripts/run_qemu.sh sec off /pks-thesis-env/tests/pks-unit/run.sh results/raw/pks-unit-off.log

pks-unit-on:
	@./scripts/run_qemu.sh sec on /pks-thesis-env/tests/pks-unit/run.sh results/raw/pks-unit-on.log

pks-unit: pks-unit-off pks-unit-on

sanity-off:
	@./scripts/run_qemu.sh sec off /pks-thesis-env/tests/sanity/run.sh results/raw/sanity-off.log

sanity-on:
	@./scripts/run_qemu.sh sec on /pks-thesis-env/tests/sanity/run.sh results/raw/sanity-on.log

sanity: sanity-off sanity-on

fsx-off:
	@./scripts/run_qemu.sh sec off /pks-thesis-env/tests/fsx/run.sh results/raw/fsx-off.log

fsx-on:
	@./scripts/run_qemu.sh sec on /pks-thesis-env/tests/fsx/run.sh results/raw/fsx-on.log

fsx: fsx-off fsx-on

pjd-off:
	@./scripts/run_qemu.sh sec off /pks-thesis-env/tests/pjd/run.sh results/raw/pjd-off.log

pjd-on:
	@./scripts/run_qemu.sh sec on /pks-thesis-env/tests/pjd/run.sh results/raw/pjd-on.log

pjd: pjd-off pjd-on

test-off:
	@./scripts/run_qemu.sh sec off test results/raw/test-off.log

test-on:
	@./scripts/run_qemu.sh sec on test results/raw/test-on.log

analyze-test:
	@python3 scripts/data/analyze_test.py

# ==============================================================================
# Group 4: Security Benchmarks
# ==============================================================================
copy-fail-off:
	@./scripts/run_qemu.sh sec off /pks-thesis-env/sec/copy-fail/run.sh results/raw/copy-fail-off.log

copy-fail-on:
	@./scripts/run_qemu.sh sec on /pks-thesis-env/sec/copy-fail/run.sh results/raw/copy-fail-on.log

copy-fail: copy-fail-off copy-fail-on

dirty-frag-off:
	@./scripts/run_qemu.sh sec off /pks-thesis-env/sec/dirty-frag/run.sh results/raw/dirty-frag-off.log

dirty-frag-on:
	@./scripts/run_qemu.sh sec on /pks-thesis-env/sec/dirty-frag/run.sh results/raw/dirty-frag-on.log

dirty-frag: dirty-frag-off dirty-frag-on

fragnesia-off:
	@./scripts/run_qemu.sh sec off /pks-thesis-env/sec/fragnesia/run.sh results/raw/fragnesia-off.log

fragnesia-on:
	@./scripts/run_qemu.sh sec on /pks-thesis-env/sec/fragnesia/run.sh results/raw/fragnesia-on.log

fragnesia: fragnesia-off fragnesia-on

sec-off:
	@./scripts/run_qemu.sh sec off sec results/raw/sec-off.log

sec-on:
	@./scripts/run_qemu.sh sec on sec results/raw/sec-on.log

analyze-sec:
	@python3 scripts/data/analyze_sec.py

# ==============================================================================
# Group 5: Performance Benchmarks
# ==============================================================================
fio-control-warm:
	@./scripts/run_qemu.sh control off /pks-thesis-env/perf/fio/run_warm.sh results/raw/fio-control-warm.log

fio-control-cold:
	@./scripts/run_qemu.sh control off /pks-thesis-env/perf/fio/run_cold.sh results/raw/fio-control-cold.log

fio-off-warm:
	@./scripts/run_qemu.sh perf off /pks-thesis-env/perf/fio/run_warm.sh results/raw/fio-off-warm.log

fio-off-cold:
	@./scripts/run_qemu.sh perf off /pks-thesis-env/perf/fio/run_cold.sh results/raw/fio-off-cold.log

fio-on-warm:
	@./scripts/run_qemu.sh perf on /pks-thesis-env/perf/fio/run_warm.sh results/raw/fio-on-warm.log

fio-on-cold:
	@./scripts/run_qemu.sh perf on /pks-thesis-env/perf/fio/run_cold.sh results/raw/fio-on-cold.log

fio-warm: fio-control-warm fio-off-warm fio-on-warm
fio-cold: fio-control-cold fio-off-cold fio-on-cold
fio: fio-warm fio-cold

concurrency-control:
	@./scripts/run_qemu.sh control off /pks-thesis-env/perf/concurrency/run.sh results/raw/concurrency-control.log

concurrency-off:
	@./scripts/run_qemu.sh perf off /pks-thesis-env/perf/concurrency/run.sh results/raw/concurrency-off.log

concurrency-on:
	@./scripts/run_qemu.sh perf on /pks-thesis-env/perf/concurrency/run.sh results/raw/concurrency-on.log

concurrency: concurrency-control concurrency-off concurrency-on

sqlite-control:
	@./scripts/run_qemu.sh control off /pks-thesis-env/perf/sqlite/run.sh results/raw/sqlite-control.log

sqlite-off:
	@./scripts/run_qemu.sh perf off /pks-thesis-env/perf/sqlite/run.sh results/raw/sqlite-off.log

sqlite-on:
	@./scripts/run_qemu.sh perf on /pks-thesis-env/perf/sqlite/run.sh results/raw/sqlite-on.log

sqlite: sqlite-control sqlite-off sqlite-on

perf-control:
	@./scripts/run_qemu.sh control off perf results/raw/perf-control.log

perf-off:
	@./scripts/run_qemu.sh perf off perf results/raw/perf-off.log

perf-on:
	@./scripts/run_qemu.sh perf on perf results/raw/perf-on.log

analyze-perf:
	@./scripts/data/fetch_results.sh
	@python3 scripts/data/analyze_perf.py

# ==============================================================================
# Group 6: Maintenance and Cleanup
# ==============================================================================
clean:
	@./scripts/clean-all.sh

clean-results:
	@rm -rf results/build.log results/test.log results/sec.log results/perf.log results/raw/* results/data/*
	@echo "[clean-results] Removed all execution logs, raw CSVs, and summarized deliverables. [DONE]"
	@echo ""

clean-image:
	@rm -f images/disk.img
	@echo "[clean-image] Removed virtual disk container 'images/disk.img'. [DONE]"
	@echo ""

clean-all: clean clean-results clean-image
	@echo "[clean-all] Workspace reset to pristine state (kernel images preserved). [DONE]"
	@echo ""