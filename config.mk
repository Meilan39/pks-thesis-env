# ==============================================================================
# config.mk - Centralized configuration for PKS Thesis Evaluation Environment
# ==============================================================================
# Variables defined here can be overridden via command line or environment.
# Example: make perf-on SMP=8 MEM=8192
# ==============================================================================

# Kernel source trees
WORKSPACE_DIR      := $(abspath $(CURDIR)/..)
DEV_KERNEL_DIR     ?= $(if $(wildcard $(WORKSPACE_DIR)/linux-5.18-rc3),$(WORKSPACE_DIR)/linux-5.18-rc3,$(WORKSPACE_DIR)/linux-pks-thesis)
CONTROL_KERNEL_DIR ?= $(if $(wildcard $(WORKSPACE_DIR)/linux-5.18-rc3),$(WORKSPACE_DIR)/linux-5.18-rc3,$(WORKSPACE_DIR)/linux-pks-thesis-control)

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
TESTS_DIR          ?= $(CURDIR)/tests
SEC_DIR            ?= $(CURDIR)/sec
PERF_DIR           ?= $(CURDIR)/perf
SCRIPTS_DIR        ?= $(CURDIR)/scripts
IMAGES_DIR         ?= $(CURDIR)/images
RESULTS_DIR        ?= $(CURDIR)/results
TOOLS_DIR          ?= $(CURDIR)/tools

# QEMU runtime configuration
QEMU_BIN           ?= qemu-system-x86_64
SMP                ?= 4
MEM                ?= 4096
CONSOLE            ?= ttyS0
BATCH_TIMEOUT_SEC  ?= 300
