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
export IMAGES_DIR RESULTS_DIR TOOLS_DIR QEMU_BIN SMP CONSOLE TASKSET_CPUS
export MEM_SEC MEM_PERF_MITIGATED MEM_PERF_CONTROL BATCH_TIMEOUT_SEC

.PHONY: all help build test test-sec bench \
        bench-control bench-mitigated bench-off parse-results plot-bench \
        check-deps test-pks-unit \
        build-sec build-perf build-control build-all \
        provision-disk update-disk \
        test-sec-off test-sec-on \
        test-sec-copyfail-off test-sec-copyfail-on test-sec-copyfail \
        test-sec-dirtyfrag-off test-sec-dirtyfrag-on test-sec-dirtyfrag \
        test-sec-fragnesia-off test-sec-fragnesia-on test-sec-fragnesia \
        test-fsx-off test-fsx-on test-fsx \
        fetch-results analyze-sec \
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
	@echo "  Primary Reproduction Commands:"
	@echo "    make build               Build all kernels and prepare disk image (tmux supported)"
	@echo "    make test                Run compliance & functional integrity suite (single QEMU boot)"
	@echo "    make test-sec            Execute end-to-end exploit validation (vulnerable vs mitigated)"
	@echo "    make bench               Execute complete A/B benchmark suite (control + mitigated + parse)"
	@echo "    make bench-control       Run baseline control benchmark VM in batch mode"
	@echo "    make bench-mitigated     Run mitigated benchmark VM with pcache_pks=on in batch mode"
	@echo "    make bench-off           Run mitigated benchmark VM with pcache_pks=off (ablation) in batch mode"
	@echo "    make parse-results       Process raw fio/sqlite JSONs into canonical benchmark_summary.csv"
	@echo "    make plot-bench          Render thesis publication figures (PDF/PNG vector graphics)"
	@echo ""
	@echo "  Granular Kernel Compilation:"
	@echo "    make build-sec           Compile security kernel (pcache_pks diagnostics)"
	@echo "    make build-perf          Compile mitigated performance kernel (pcache_pks)"
	@echo "    make build-control       Compile baseline upstream control kernel"
	@echo "    make build-all           Synchronously compile all three kernel configurations"
	@echo ""
	@echo "  Disk Image Lifecycle:"
	@echo "    make provision-disk      Bootstrap and partition fresh 8GB Debian disk"
	@echo "    make update-disk         Incrementally sync guest-assets into disk image"
	@echo ""
	@echo "  Granular Security Validation:"
	@echo "    make test-sec-copyfail   Run Copy Fail exploit independently (A/B test)"
	@echo "    make test-sec-dirtyfrag  Run Dirty Frag exploit independently (A/B test)"
	@echo "    make test-sec-fragnesia  Run Fragnesia exploit independently (A/B test)"
	@echo "    make analyze-sec         Parse sec logs and display report"
	@echo ""
	@echo "  Granular Compliance & Functional Integrity:"
	@echo "    make test-fsx-off        Run fsx filesystem exerciser with pcache_pks=off"
	@echo "    make test-fsx-on         Run fsx filesystem exerciser with pcache_pks=on"
	@echo "    make test-fsx            Execute both off/on fsx tests and summarize results"
	@echo "    make test-pks-unit       Run low-level in-kernel PKS self-test (debugfs)"
	@echo ""
	@echo "  Interactive Debugging Shells:"
	@echo "    make run-sec-off         Interactive serial console (pcache_pks=off)"
	@echo "    make run-sec-on          Interactive serial console (pcache_pks=on)"
	@echo "    make run-perf            Interactive serial console (mitigated kernel)"
	@echo "    make run-control         Interactive serial console (control kernel)"
	@echo ""
	@echo "  Environment & Cleanup:"
	@echo "    make check-deps          Verify host tools and dependencies"
	@echo "    make fetch-results       Extract JSONs & logs from disk image to host"
	@echo "    make clean-results       Remove host-side logs and extracted results"
	@echo "    make clean-all           Remove results and disk image"
	@echo "======================================================================"

# ==============================================================================
# Primary Reproduction Targets
# ==============================================================================
build:
	@$(SCRIPTS_DIR)/build_all.sh

test:
	@$(SCRIPTS_DIR)/run_compliance.sh

bench: bench-control bench-off bench-mitigated fetch-results parse-results
	@echo "======================================================================"
	@echo " Benchmark Suite Execution & Processing Complete"
	@echo "======================================================================"
	@echo "  Summary dataset: $(RESULTS_DIR)/processed/benchmark_summary.csv"
	@echo "  To render publication figures, run: make plot-bench"
	@echo "======================================================================"

bench-control:
	@$(SCRIPTS_DIR)/run_qemu_control.sh --batch

bench-mitigated:
	@$(SCRIPTS_DIR)/run_qemu_perf.sh --batch on

bench-off:
	@$(SCRIPTS_DIR)/run_qemu_perf.sh --batch off

parse-results:
	@python3 $(SCRIPTS_DIR)/parse_results.py $(RESULTS_DIR)/raw $(RESULTS_DIR)/processed/benchmark_summary.csv $(RESULTS_DIR)/processed/run_metadata.json

plot-bench:
	@python3 $(TOOLS_DIR)/plotting/plot_thesis_figures.py $(RESULTS_DIR)/processed/benchmark_summary.csv $(RESULTS_DIR)/processed/figures

# ==============================================================================
# Kernel Build Targets (Granular)
# ==============================================================================
build-sec:
	@$(SCRIPTS_DIR)/build_sec.sh $(DEV_KERNEL_DIR)

build-perf:
	@$(SCRIPTS_DIR)/build_perf.sh $(DEV_KERNEL_DIR)

build-control:
	@$(SCRIPTS_DIR)/build_control.sh $(CONTROL_KERNEL_DIR)

build-all:
	@$(SCRIPTS_DIR)/build_all.sh --direct

# ==============================================================================
# Disk Lifecycle Targets
# ==============================================================================
provision-disk:
	@$(SCRIPTS_DIR)/provision_disk.sh $(DISK_IMG)

update-disk:
	@$(SCRIPTS_DIR)/update_disk.sh $(DISK_IMG)

# ==============================================================================
# Automated Security Validation (Exploit Neutralization)
# ==============================================================================
test-sec-copyfail-off:
	@$(SCRIPTS_DIR)/run_qemu_sec.sh off --batch sec_copyfail

test-sec-copyfail-on:
	@$(SCRIPTS_DIR)/run_qemu_sec.sh on --batch sec_copyfail

test-sec-copyfail: test-sec-copyfail-off test-sec-copyfail-on
	@python3 $(SCRIPTS_DIR)/analyze_sec.py --off-log $(RESULTS_DIR)/sec_copyfail_off.log --on-log $(RESULTS_DIR)/sec_copyfail_on.log

test-sec-dirtyfrag-off:
	@$(SCRIPTS_DIR)/run_qemu_sec.sh off --batch sec_dirtyfrag

test-sec-dirtyfrag-on:
	@$(SCRIPTS_DIR)/run_qemu_sec.sh on --batch sec_dirtyfrag

test-sec-dirtyfrag: test-sec-dirtyfrag-off test-sec-dirtyfrag-on
	@python3 $(SCRIPTS_DIR)/analyze_sec.py --off-log $(RESULTS_DIR)/sec_dirtyfrag_off.log --on-log $(RESULTS_DIR)/sec_dirtyfrag_on.log

test-sec-fragnesia-off:
	@$(SCRIPTS_DIR)/run_qemu_sec.sh off --batch sec_fragnesia

test-sec-fragnesia-on:
	@$(SCRIPTS_DIR)/run_qemu_sec.sh on --batch sec_fragnesia

test-sec-fragnesia: test-sec-fragnesia-off test-sec-fragnesia-on
	@python3 $(SCRIPTS_DIR)/analyze_sec.py --off-log $(RESULTS_DIR)/sec_fragnesia_off.log --on-log $(RESULTS_DIR)/sec_fragnesia_on.log

test-sec: test-sec-copyfail test-sec-dirtyfrag test-sec-fragnesia
	@echo ""
	@echo "======================================================================"
	@echo " Exploit Mitigation Evaluation Complete (Copy Fail, Dirty Frag, Fragnesia)"
	@echo "======================================================================"
	@python3 $(SCRIPTS_DIR)/analyze_sec.py

analyze-sec:
	@python3 $(SCRIPTS_DIR)/analyze_sec.py --off-log $(RESULTS_DIR)/sec_off.log --on-log $(RESULTS_DIR)/sec_on.log

# ==============================================================================
# Fail-Open & Functional Integrity Testing (fsx Exerciser)
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
# Results Harvesting
# ==============================================================================
fetch-results:
	@$(SCRIPTS_DIR)/fetch_results.sh $(RESULTS_DIR)/extracted

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
# Diagnostics & Sanity Checks (Optional Pre-flight / Low-level Verification)
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

# ==============================================================================
# Cleanup
# ==============================================================================
clean-results:
	@echo "Removing results and extracted artifacts..."
	@rm -rf $(RESULTS_DIR)/*
	@mkdir -p $(RESULTS_DIR)/raw $(RESULTS_DIR)/processed/figures $(RESULTS_DIR)/extracted

clean-all: clean-results
	@echo "Removing disk image container..."
	@rm -f $(DISK_IMG)