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
        test-off test-on analyze-test \
        sec-off sec-on analyze-sec \
        perf-control perf-off perf-on analyze-perf \
        clean clean-results clean-image clean-build clean-all

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
	@echo "    make test               Execute compliance & integrity test suite"
	@echo "    make sec                Execute 3-way exploit neutralization evaluation"
	@echo "    make perf               Execute full A/B performance benchmark sweeps"
	@echo ""
	@echo "  Kernel & Disk Lifecycle:"
	@echo "    make build-sec          Compile security diagnostic kernel"
	@echo "    make build-perf         Compile performance mitigated kernel"
	@echo "    make build-control      Compile baseline pristine upstream Linux v5.18-rc3"
	@echo "    make disk-provision     Bootstrap Debian Bookworm and partition images/disk.img"
	@echo "    make disk-update        Synchronize /pks-thesis-env into virtual disk image"
	@echo "    make compile            Compile all in-guest evaluation binaries"
	@echo "    make run-qemu           Launch interactive serial debugging console"
	@echo "    make end-qemu           Terminate all active QEMU instances"
	@echo ""
	@echo "  Compliance & Integrity (Invoked by 'make test'):"
	@echo "    make test-off           Execute compliance suite on unmitigated kernel"
	@echo "    make test-on            Execute compliance suite on mitigated kernel"
	@echo "    make analyze-test       Synthesize compliance evaluation report"
	@echo ""
	@echo "  Security Evaluation (Invoked by 'make sec'):"
	@echo "    make sec-off            Execute exploit vectors on unmitigated kernel"
	@echo "    make sec-on             Execute exploit vectors on mitigated kernel"
	@echo "    make analyze-sec        Synthesize 3-way exploit neutralization matrix"
	@echo ""
	@echo "  Performance Evaluation (Invoked by 'make perf'):"
	@echo "    make perf-control       Execute benchmark suite on baseline control kernel"
	@echo "    make perf-off           Execute benchmark suite on unmitigated kernel"
	@echo "    make perf-on            Execute benchmark suite on mitigated kernel"
	@echo "    make analyze-perf       Synthesize normalized A/B performance summary"
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
	@./scripts/run_qemu.sh $(or $(VARIANT),perf) $(or $(MODE),on) shell

end-qemu:
	@killall -9 qemu-system-x86_64 2>/dev/null || true
	@echo "[end-qemu] Terminated all active QEMU emulator instances. [DONE]"
	@echo ""

# ==============================================================================
# Group 3: Unit and Compliance Testing
# ==============================================================================
test-off:
	@./scripts/run_qemu.sh sec off test results/raw/test-off.log

test-on:
	@./scripts/run_qemu.sh sec on test results/raw/test-on.log

analyze-test:
	@python3 scripts/data/analyze_test.py

# ==============================================================================
# Group 4: Security Benchmarks
# ==============================================================================
sec-off:
	@./scripts/run_qemu.sh sec off sec results/raw/sec-off.log

sec-on:
	@./scripts/run_qemu.sh sec on sec results/raw/sec-on.log

analyze-sec:
	@python3 scripts/data/analyze_sec.py

# ==============================================================================
# Group 5: Performance Benchmarks
# ==============================================================================
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

clean-build:
	@rm -f build_control/arch/x86/boot/bzImage build_perf/arch/x86/boot/bzImage build_sec/arch/x86/boot/bzImage
	@echo "[clean-build] Removed all compiled bzImage kernel images. [DONE]"
	@echo ""

clean-all: clean clean-results clean-image clean-build
	@echo "[clean-all] Workspace reset to pristine pre-build state. [DONE]"
	@echo ""