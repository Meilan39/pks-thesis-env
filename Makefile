# ==============================================================================
# Makefile - Top-level orchestration for the PKS evaluation testbed.
#
# Only high-level verbs live here (each owns its own tee'd log). Granular runs
# are done by calling a subtree's run.sh directly, e.g.:
#     ./sec/copy-fail/run.sh        ./perf/fio/run.sh        ./build/sec/run.sh
# ==============================================================================
SHELL := /bin/bash
.DEFAULT_GOAL := help

-include config.mk
export DEV_KERNEL_DIR CONTROL_KERNEL_DIR DISK_IMG DISK_SIZE ROOTFS_SIZE
export DEBIAN_SUITE DEBIAN_ARCH DEBIAN_MIRROR EXECUTOR QEMU_BIN SMP MEM BATCH_TIMEOUT_SEC

$(shell mkdir -p results/data images)

.PHONY: help preflight build disk test sec perf run-qemu end-qemu \
        clean clean-results clean-image clean-all

help:
	@echo "PKS Evaluation Testbed"
	@echo "  make build   Compile the three guest kernels (control, sec, perf)"
	@echo "  make disk    Provision the guest image (once) + refresh autorun"
	@echo "  make test    Compliance axis  (pks-unit, sanity, fsx, pjd) off & on"
	@echo "  make sec     Security axis    (copy-fail, dirty-frag, fragnesia) off & on"
	@echo "  make perf    Performance axis (fio, concurrency, sqlite) control/off/on"
	@echo ""
	@echo "  make run-qemu [VARIANT=perf MODE=on]   Interactive serial console"
	@echo "  make end-qemu                          Kill stray QEMU instances"
	@echo "  make clean | clean-results | clean-image | clean-all"
	@echo ""
	@echo "  Granular runs: call a subtree run.sh directly (e.g. ./sec/copy-fail/run.sh)"

preflight:
	@./preflight.sh

build:
	@set -o pipefail; ./build/run.sh 2>&1 | tee results/build.log

disk:
	@set -o pipefail; ./disk/run.sh 2>&1 | tee results/disk.log

test: preflight
	@set -o pipefail; ./test/run.sh 2>&1 | tee results/test.log

sec: preflight
	@set -o pipefail; ./sec/run.sh 2>&1 | tee results/sec.log

perf: preflight
	@set -o pipefail; ./perf/run.sh 2>&1 | tee results/perf.log

run-qemu:
	@./exec/$(or $(EXECUTOR),qemu).sh $(or $(VARIANT),perf) $(or $(MODE),on) shell

end-qemu:
	@killall -9 $(or $(QEMU_BIN),qemu-system-x86_64) 2>/dev/null || true
	@echo "[end-qemu] terminated stray QEMU instances."

# ------------------------------------------------------------------------------
# Maintenance. Kernel build trees are never touched (the preservation invariant).
# ------------------------------------------------------------------------------
clean:
	@find test sec perf -name '*.o' -delete 2>/dev/null || true
	@rm -f test/fsx/fsx test/pjd/pjdfstest test/sanity/pks_sanity_test test/pks-unit/test_pks \
	       sec/dirty-frag/exp sec/fragnesia/exp 2>/dev/null || true
	@echo "[clean] removed compiled evaluation binaries."

clean-results:
	@rm -rf results/*.log results/*.json results/.substrate results/data/* results/raw 2>/dev/null || true
	@find build disk test sec perf \( -name 'result.log' -o -name 'raw.log' -o -name 'raw-*.log' -o -name raw \) \
	        -exec rm -rf {} + 2>/dev/null || true
	@echo "[clean-results] removed summaries, result.logs, raw transcripts, and per-leaf raw/ dirs."

clean-image:
	@rm -f images/disk.img
	@echo "[clean-image] removed images/disk.img."

clean-all: clean clean-results clean-image
	@echo "[clean-all] workspace reset (kernel images preserved)."
