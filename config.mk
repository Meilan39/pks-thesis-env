# ==============================================================================
# config.mk - Static configuration for the PKS evaluation testbed.
# Override on the command line or environment, e.g.  make perf SMP=8 MEM=8192
# ==============================================================================

# Kernel source trees (external, version-agnostic). Builds output to
# $(TREE)/build_{sec,perf,control}/arch/x86/boot/bzImage.
DEV_KERNEL_DIR     ?= $(HOME)/src/linux-pks-thesis
CONTROL_KERNEL_DIR ?= $(HOME)/src/linux-pks-thesis-control

# Persistent guest disk image.
DISK_IMG           ?= $(CURDIR)/images/disk.img
DISK_SIZE          ?= 8G
ROOTFS_SIZE        ?= 6G

# Debootstrap settings (only consulted when the image is first provisioned).
DEBIAN_SUITE       ?= bookworm
DEBIAN_ARCH        ?= amd64
DEBIAN_MIRROR      ?= http://deb.debian.org/debian

# Execution substrate: auto | qemu | baremetal.
#   auto      -> baremetal when this host runs the patched PKS kernel, else qemu
#   qemu      -> QEMU/KVM guest adapter (exec/qemu.sh); KVM+PKS when available
#   baremetal -> run leaves natively on this PKS host (exec/baremetal.sh)
EXECUTOR           ?= auto

# Bare-metal substrate (exec/baremetal.sh); consulted only when EXECUTOR
# resolves to baremetal. PROTECTED_DEV is the dedicated evaluation partition --
# NEVER the rootfs, since the security leaves overwrite it. It is mounted at
# PROTECTED_MNT (which the leaves hard-code as /mnt/protected), with
# -o pks_pagecache under 'on'.
PROTECTED_DEV      ?= /dev/sdb1
PROTECTED_MNT      ?= /mnt/protected

# Build real-hardware drivers into the kernels (configs/baremetal.config) so the
# bzImage can boot a physical host. Set to 1 for native bare-metal sweeps:
#   make build BAREMETAL=1
BAREMETAL          ?= 0

# QEMU runtime.
QEMU_BIN           ?= qemu-system-x86_64
SMP                ?= 4
MEM                ?= 4096
# Batch run timeout in seconds (0 = disabled, runs until guest shutdown).
BATCH_TIMEOUT_SEC  ?= 0
