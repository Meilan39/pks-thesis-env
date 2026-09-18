# ==============================================================================
# config.mk - Centralized configuration for PKS Thesis Evaluation Environment
# ==============================================================================
# Variables defined here can be overridden via command line or environment.
# Example: make test-sec-on SMP=8 MEM_SEC=8G
# ==============================================================================

# Kernel source trees
WORKSPACE_DIR      := $(abspath $(CURDIR)/..)
DEV_KERNEL_DIR     ?= $(if $(wildcard $(WORKSPACE_DIR)/linux-pks-thesis),$(WORKSPACE_DIR)/linux-pks-thesis,$(if $(wildcard $(WORKSPACE_DIR)/linux-5.18-rc3),$(WORKSPACE_DIR)/linux-5.18-rc3,$(WORKSPACE_DIR)/linux-pks-thesis))
CONTROL_KERNEL_DIR ?= $(WORKSPACE_DIR)/linux-pks-thesis-control

# Storage configuration
DISK_IMG           ?= $(CURDIR)/images/disk.img
DISK_SIZE          ?= 8G
ROOTFS_SIZE        ?= 6G
PROT_SIZE          ?= 2G

# Debootstrap distribution settings
DEBIAN_SUITE       ?= bookworm
DEBIAN_ARCH        ?= amd64
DEBIAN_MIRROR      ?= http://deb.debian.org/debian

# Directory structure
SCRIPTS_DIR        ?= $(CURDIR)/scripts
GUEST_ASSETS_DIR   ?= $(CURDIR)/guest-assets
IMAGES_DIR         ?= $(CURDIR)/images
RESULTS_DIR        ?= $(CURDIR)/results
TOOLS_DIR          ?= $(CURDIR)/tools

# QEMU runtime configuration
QEMU_BIN           ?= qemu-system-x86_64
SMP                ?= 4
CONSOLE            ?= ttyS0
TASKSET_CPUS       ?=

# Memory configuration
# Security validation: 4GB RAM
MEM_SEC            ?= 4G

# Performance micro-benchmarking:
# Mitigated VM boots with 4096MB total (kernel reserves 256MB static pool -> 3840MB usable)
MEM_PERF_MITIGATED ?= 4096M
# Control VM boots with 3840MB total (matches usable pool of mitigated VM)
MEM_PERF_CONTROL   ?= 3840M

# Headless batch test execution timeout (seconds)
BATCH_TIMEOUT_SEC  ?= 300
