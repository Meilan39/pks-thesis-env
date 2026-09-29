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

# Execution substrate. `qemu` today; `baremetal` is the future PKS-host adapter.
EXECUTOR           ?= qemu

# QEMU runtime.
QEMU_BIN           ?= qemu-system-x86_64
SMP                ?= 4
MEM                ?= 4096
# TCG (no KVM on this host) boots and runs several times slower than native, so
# a full guest boot + suite needs a generous cap. Raise it if a run ends in a
# 124 timeout mid-suite; lower it (or drop SMP) once you know the real duration.
BATCH_TIMEOUT_SEC  ?= 900
