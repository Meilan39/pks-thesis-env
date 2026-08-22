# Top-level orchestration for the PKS evaluation pipeline
SHELL := /bin/bash
ENV_DIR := $(CURDIR)
SCRIPTS_DIR := $(ENV_DIR)/scripts
GUEST_ASSETS := $(ENV_DIR)/guest-assets
IMAGES_DIR := $(ENV_DIR)/images
RESULTS_DIR := $(ENV_DIR)/results

KERNEL_DEV ?= $(HOME)/src/linux-pks-thesis
KERNEL_CONTROL ?= $(HOME)/src/linux-control
DISK_IMG ?= $(IMAGES_DIR)/disk.img

.PHONY: all build-sec build-perf build-control provision-image \
        run-sec-off run-sec-on run-perf run-control clean

all: build-sec build-perf build-control

## Build kernels
build-sec:
	@echo "=== Building security kernel (build_sec) ==="
	$(SCRIPTS_DIR)/build_sec.sh $(KERNEL_DEV)

build-perf:
	@echo "=== Building performance kernel (build_perf, dev) ==="
	$(SCRIPTS_DIR)/build_perf.sh $(KERNEL_DEV)

build-control:
	@echo "=== Building control kernel (build_perf, control) ==="
	$(SCRIPTS_DIR)/build_control.sh $(KERNEL_CONTROL)

## Provision the persistent disk image
provision-image:
	@echo "=== Provisioning disk image: $(DISK_IMG) ==="
	$(SCRIPTS_DIR)/provision_disk.sh $(DISK_IMG)

## Run security validation
run-sec-off:
	$(SCRIPTS_DIR)/run_qemu_sec.sh off

run-sec-on:
	$(SCRIPTS_DIR)/run_qemu_sec.sh on

## Run performance benchmarks
run-perf:
	$(SCRIPTS_DIR)/run_qemu_perf.sh

run-control:
	$(SCRIPTS_DIR)/run_qemu_control.sh

clean:
	@echo "Removing results and temporary files"
	rm -rf $(RESULTS_DIR)/*