# ==============================================================================
# Makefile - Top-level Orchestration for PKS Thesis Evaluation Pipeline
# ==============================================================================
# Controls kernel compilation, disk provisioning, automated batch tests,
# interactive debugging, and benchmark harvesting/analysis.
# ==============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

-include config.mk

# Export variables for child scripts
export DEV_KERNEL_DIR CONTROL_KERNEL_DIR DISK_IMG DISK_SIZE ROOTFS_SIZE PROT_SIZE
export DEBIAN_SUITE DEBIAN_ARCH DEBIAN_MIRROR SCRIPTS_DIR GUEST_ASSETS_DIR
export IMAGES_DIR RESULTS_DIR QEMU_BIN SMP CONSOLE TASKSET_CPUS
export MEM_SEC MEM_PERF_MITIGATED MEM_PERF_CONTROL BATCH_TIMEOUT_SEC

.PHONY: all help check-deps \
        build-sec build-perf build-control build-all \
        provision-disk update-disk \
        test-pks-unit test-sec-off test-sec-on test-sec \
        test-fsx-off test-fsx-on test-fsx \
        bench-control bench-mitigated bench-all \
        fetch-results analyze-bench \
        run-sec-off run-sec-on run-perf run-control \
        clean-results clean-all

# ==============================================================================
# Help Target
# ==============================================================================
help:
	@echo "======================================================================"
	@echo " PKS Thesis Evaluation Environment - Available Commands"
	@echo "======================================================================"
	@echo ""
	@echo "  Kernel Compilation:"
	@echo "    make build-sec           Compile security kernel (pcache_pks diagnostics)"
	@echo "    make build-perf          Compile mitigated performance kernel (pcache_pks)"
	@echo "    make build-control       Compile baseline upstream control kernel"
	@echo "    make build-all           Compile all three kernel configurations"
	@echo ""
	@echo "  Disk Image Lifecycle:"
	@echo "    make provision-disk      Bootstrap and partition fresh 8GB Debian disk"
	@echo "    make update-disk         Incrementally sync guest-assets into disk image"
	@echo ""
	@echo "  Automated Security Validation (Headless Batch):"
	@echo "    make test-pks-unit       Run built-in in-kernel PKS unit tests (debugfs)"
	@echo "    make test-sec-off        Run exploit suite with pcache_pks=off (vulnerable)"
	@echo "    make test-sec-on         Run exploit suite with pcache_pks=on (mitigated)"
	@echo "    make test-sec            Execute both off/on tests and summarize results"
	@echo "    make test-fsx-off        Run fsx filesystem exerciser with pcache_pks=off"
	@echo "    make test-fsx-on         Run fsx filesystem exerciser with pcache_pks=on"
	@echo "    make test-fsx            Execute both off/on fsx tests and summarize results"
	@echo ""
	@echo "  Automated Micro-benchmarks (Headless Batch):"
	@echo "    make bench-control       Run fio write/read suite on control kernel"
	@echo "    make bench-mitigated     Run fio write/read suite on mitigated kernel"
	@echo "    make bench-all           Run control + mitigated benchmarks and analyze"
	@echo ""
	@echo "  Artifact Extraction & Analysis:"
	@echo "    make fetch-results       Extract JSONs & logs from disk image to host"
	@echo "    make analyze-bench       Parse extracted fio JSONs and print overhead"
	@echo ""
	@echo "  Interactive Debugging Shells:"
	@echo "    make run-sec-off         Interactive serial console (pcache_pks=off)"
	@echo "    make run-sec-on          Interactive serial console (pcache_pks=on)"
	@echo "    make run-perf            Interactive serial console (mitigated kernel)"
	@echo "    make run-control         Interactive serial console (control kernel)"
	@echo ""
	@echo "  Environment & Cleanup:"
	@echo "    make check-deps          Verify host tools and dependencies"
	@echo "    make clean-results       Remove host-side logs and extracted results"
	@echo "    make clean-all           Remove results and disk image"
	@echo "======================================================================"

# ==============================================================================
# Pre-flight Dependency Check
# ==============================================================================
check-deps:
	@$(SCRIPTS_DIR)/common.sh
	@echo "Checking host dependencies..."
	@for cmd in $(QEMU_BIN) gcc make sfdisk losetup mkfs.ext4 debootstrap sudo python3; do \
		if command -v $$cmd >/dev/null 2>&1; then \
			printf "  [OK]   %-16s found\n" "$$cmd"; \
		else \
			printf "  [MISS] %-16s NOT FOUND\n" "$$cmd"; \
		fi; \
	done

# ==============================================================================
# Kernel Build Targets
# ==============================================================================
build-sec:
	@$(SCRIPTS_DIR)/build_sec.sh $(DEV_KERNEL_DIR)

build-perf:
	@$(SCRIPTS_DIR)/build_perf.sh $(DEV_KERNEL_DIR)

build-control:
	@$(SCRIPTS_DIR)/build_control.sh $(CONTROL_KERNEL_DIR)

build-all: build-sec build-perf build-control

# ==============================================================================
# Disk Lifecycle Targets
# ==============================================================================
provision-disk:
	@$(SCRIPTS_DIR)/provision_disk.sh $(DISK_IMG)

update-disk:
	@$(SCRIPTS_DIR)/update_disk.sh $(DISK_IMG)

# ==============================================================================
# Automated Security Testing (Batch Mode)
# ==============================================================================
test-pks-unit:
	@$(SCRIPTS_DIR)/run_qemu_sec.sh on --batch unit
	@if [ -f "$(RESULTS_DIR)/pks_unit.log" ]; then \
		echo ""; \
		echo "======================================================================"; \
		echo " PKS In-Kernel Self-Test Log Output"; \
		echo "======================================================================"; \
		grep -E "(Test|Summary|pks_test|PASS|FAIL)" "$(RESULTS_DIR)/pks_unit.log" || true; \
		echo "======================================================================"; \
	fi

test-sec-off:
	@$(SCRIPTS_DIR)/run_qemu_sec.sh off --batch

test-sec-on:
	@$(SCRIPTS_DIR)/run_qemu_sec.sh on --batch

test-sec: test-sec-off test-sec-on
	@echo ""
	@echo "======================================================================"
	@echo " Security Validation Summary (A/B Test)"
	@echo "======================================================================"
	@echo "  pcache_pks=off Log: $(RESULTS_DIR)/sec_off.log"
	@echo "  pcache_pks=on  Log: $(RESULTS_DIR)/sec_on.log"
	@echo "----------------------------------------------------------------------"
	@if [ -f "$(RESULTS_DIR)/sec_off.log" ]; then \
		echo "Off state results:"; \
		grep -E "(RESULT:|pre-run|post-run)" "$(RESULTS_DIR)/sec_off.log" || true; \
	fi
	@echo "----------------------------------------------------------------------"
	@if [ -f "$(RESULTS_DIR)/sec_on.log" ]; then \
		echo "On state results:"; \
		grep -E "(RESULT:|pre-run|post-run|Security event|Oops)" "$(RESULTS_DIR)/sec_on.log" || true; \
	fi
	@echo "======================================================================"

# ==============================================================================
# Automated Filesystem Exerciser Testing (fsx - Batch Mode)
# ==============================================================================
test-fsx-off:
	@$(SCRIPTS_DIR)/run_qemu_sec.sh off --batch fsx

test-fsx-on:
	@$(SCRIPTS_DIR)/run_qemu_sec.sh on --batch fsx

test-fsx: test-fsx-off test-fsx-on
	@echo ""
	@echo "======================================================================"
	@echo " File System Exerciser (fsx) Validation Summary"
	@echo "======================================================================"
	@echo "  pcache_pks=off Log: $(RESULTS_DIR)/fsx_off.log"
	@echo "  pcache_pks=on  Log: $(RESULTS_DIR)/fsx_on.log"
	@echo "----------------------------------------------------------------------"
	@if [ -f "$(RESULTS_DIR)/fsx_off.log" ]; then \
		echo "Off state fsx results:"; \
		grep -E "(Test|Summary|PASS|FAIL|SUCCESS)" "$(RESULTS_DIR)/fsx_off.log" || true; \
	fi
	@echo "----------------------------------------------------------------------"
	@if [ -f "$(RESULTS_DIR)/fsx_on.log" ]; then \
		echo "On state fsx results:"; \
		grep -E "(Test|Summary|PASS|FAIL|SUCCESS)" "$(RESULTS_DIR)/fsx_on.log" || true; \
	fi
	@echo "======================================================================"

# ==============================================================================
# Automated Benchmarking (Batch Mode)
# ==============================================================================
bench-control:
	@mkdir -p $(RESULTS_DIR)/extracted/bench/control
	@$(SCRIPTS_DIR)/run_qemu_control.sh --batch
	@$(SCRIPTS_DIR)/fetch_results.sh $(RESULTS_DIR)/extracted_control
	@cp -a $(RESULTS_DIR)/extracted_control/bench/*.json $(RESULTS_DIR)/extracted/bench/control/ 2>/dev/null || true

bench-mitigated:
	@mkdir -p $(RESULTS_DIR)/extracted/bench/mitigated
	@$(SCRIPTS_DIR)/run_qemu_perf.sh --batch
	@$(SCRIPTS_DIR)/fetch_results.sh $(RESULTS_DIR)/extracted_mitigated
	@cp -a $(RESULTS_DIR)/extracted_mitigated/bench/*.json $(RESULTS_DIR)/extracted/bench/mitigated/ 2>/dev/null || true

bench-all: bench-control bench-mitigated analyze-bench

# ==============================================================================
# Results Harvesting and Parsing
# ==============================================================================
fetch-results:
	@$(SCRIPTS_DIR)/fetch_results.sh $(RESULTS_DIR)/extracted

analyze-bench:
	@$(SCRIPTS_DIR)/analyze_bench.py \
		--control-dir $(RESULTS_DIR)/extracted/bench/control \
		--mitigated-dir $(RESULTS_DIR)/extracted/bench/mitigated

# ==============================================================================
# Interactive QEMU Shells (Manual / Debugging Mode)
# ==============================================================================
run-sec-off:
	@$(SCRIPTS_DIR)/run_qemu_sec.sh off --interactive

run-sec-on:
	@$(SCRIPTS_DIR)/run_qemu_sec.sh on --interactive

run-perf:
	@$(SCRIPTS_DIR)/run_qemu_perf.sh --interactive

run-control:
	@$(SCRIPTS_DIR)/run_qemu_control.sh --interactive

# ==============================================================================
# Cleanup
# ==============================================================================
clean-results:
	@echo "Removing results and extracted artifacts..."
	@rm -rf $(RESULTS_DIR)/*

clean-all: clean-results
	@echo "Removing disk image container..."
	@rm -f $(DISK_IMG)