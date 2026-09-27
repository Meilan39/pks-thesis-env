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
        clean clean-results clean-image clean-control clean-perf clean-sec clean-build clean-all

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
	@echo "    make clean-build        Remove compiled kernel bzImage binaries"
	@echo "    make clean-all          Reset workspace to pristine state"
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
		echo "  Security Kernel:     $$(ls -lh build_sec/arch/x86/boot/bzImage 2>/dev/null | awk '{print $$5}')  [READY]"; \
		echo "  Performance Kernel:  $$(ls -lh build_perf/arch/x86/boot/bzImage 2>/dev/null | awk '{print $$5}') [READY]"; \
		echo "  Control Kernel:      $$(ls -lh build_control/arch/x86/boot/bzImage 2>/dev/null | awk '{print $$5}') [READY]"; \
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
	@./scripts/build/build_sec.sh > results/raw/build-sec.log 2>&1 || (cat results/raw/build-sec.log && exit 1)

build-perf:
	@./scripts/build/build_perf.sh > results/raw/build-perf.log 2>&1 || (cat results/raw/build-perf.log && exit 1)

build-control:
	@./scripts/build/build_control.sh > results/raw/build-control.log 2>&1 || (cat results/raw/build-control.log && exit 1)

disk-provision:
	@./scripts/disk/disk_provision.sh > results/raw/disk-provision.log 2>&1 || (cat results/raw/disk-provision.log && exit 1)

disk-update:
	@./scripts/disk/disk_update.sh > results/raw/disk-update.log 2>&1 || (cat results/raw/disk-update.log && exit 1)

compile:
	@./scripts/compile-all.sh > results/raw/compile.log 2>&1 || (cat results/raw/compile.log && exit 1)

run-qemu:
	@./scripts/run/run_qemu.sh $(or $(VARIANT),perf) $(or $(MODE),on) shell

end-qemu:
	@killall -9 qemu-system-x86_64 2>/dev/null || true
	@echo "[end-qemu] Terminated all active QEMU emulator instances. [DONE]"
	@echo ""

# ==============================================================================
# Group 3: Unit and Compliance Testing
# ==============================================================================
pks-unit-off:
	@./scripts/run/run_test.sh pks-unit off

pks-unit-on:
	@./scripts/run/run_test.sh pks-unit on

pks-unit: pks-unit-on

sanity-off:
	@./scripts/run/run_test.sh sanity off

sanity-on:
	@./scripts/run/run_test.sh sanity on

sanity: sanity-on

fsx-off:
	@./scripts/run/run_test.sh fsx off

fsx-on:
	@./scripts/run/run_test.sh fsx on

fsx: fsx-on

pjd-off:
	@./scripts/run/run_test.sh pjd off

pjd-on:
	@./scripts/run/run_test.sh pjd on

pjd: pjd-on

test-off:
	@./scripts/run/run_test.sh all off

test-on:
	@./scripts/run/run_test.sh all on

analyze-test:
	@python3 scripts/data/analyze_test.py

# ==============================================================================
# Group 4: Security Benchmarks
# ==============================================================================
copy-fail-off:
	@./scripts/run/run_sec.sh copy-fail off

copy-fail-on:
	@./scripts/run/run_sec.sh copy-fail on

copy-fail: copy-fail-on

dirty-frag-off:
	@./scripts/run/run_sec.sh dirty-frag off

dirty-frag-on:
	@./scripts/run/run_sec.sh dirty-frag on

dirty-frag: dirty-frag-on

fragnesia-off:
	@./scripts/run/run_sec.sh fragnesia off

fragnesia-on:
	@./scripts/run/run_sec.sh fragnesia on

fragnesia: fragnesia-on

sec-off:
	@./scripts/run/run_sec.sh all off

sec-on:
	@./scripts/run/run_sec.sh all on

analyze-sec:
	@python3 scripts/data/analyze_sec.py

# ==============================================================================
# Group 5: Performance Benchmarks
# ==============================================================================
fio-control-warm:
	@./scripts/run/run_perf.sh fio control warm

fio-control-cold:
	@./scripts/run/run_perf.sh fio control cold

fio-off-warm:
	@./scripts/run/run_perf.sh fio off warm

fio-off-cold:
	@./scripts/run/run_perf.sh fio off cold

fio-on-warm:
	@./scripts/run/run_perf.sh fio on warm

fio-on-cold:
	@./scripts/run/run_perf.sh fio on cold

fio-warm: fio-control-warm fio-off-warm fio-on-warm
fio-cold: fio-control-cold fio-off-cold fio-on-cold
fio: fio-warm fio-cold

concurrency-control:
	@./scripts/run/run_perf.sh concurrency control

concurrency-off:
	@./scripts/run/run_perf.sh concurrency off

concurrency-on:
	@./scripts/run/run_perf.sh concurrency on

concurrency: concurrency-control concurrency-off concurrency-on

sqlite-control:
	@./scripts/run/run_perf.sh sqlite control

sqlite-off:
	@./scripts/run/run_perf.sh sqlite off

sqlite-on:
	@./scripts/run/run_perf.sh sqlite on

sqlite: sqlite-control sqlite-off sqlite-on

perf-control:
	@./scripts/run/run_perf.sh all control

perf-off:
	@./scripts/run/run_perf.sh all off

perf-on:
	@./scripts/run/run_perf.sh all on

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

clean-control:
	@rm -f build_control/arch/x86/boot/bzImage
	@echo "[clean-control] Removed compiled bzImage for control baseline. [DONE]"
	@echo ""

clean-perf:
	@rm -f build_perf/arch/x86/boot/bzImage
	@echo "[clean-perf] Removed compiled bzImage for performance kernel. [DONE]"
	@echo ""

clean-sec:
	@rm -f build_sec/arch/x86/boot/bzImage
	@echo "[clean-sec] Removed compiled bzImage for security kernel. [DONE]"
	@echo ""

clean-build: clean-control clean-perf clean-sec
	@echo "[clean-build] Removed all compiled bzImage kernel images. [DONE]"
	@echo ""

clean-all: clean clean-results clean-image clean-build
	@echo "[clean-all] Workspace reset to pristine pre-build state. [DONE]"
	@echo ""