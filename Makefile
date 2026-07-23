# LVBS out-of-tree build.
#
# A single Linux kernel is built with VBS/HEKI plus the KVM VM-planes backend.
# The same kernel image serves both plane 0 (normal) and plane 1 (secure):
# plane 0 boots the compressed bzImage and plane 1 runs the uncompressed
# vmlinux ELF. Kernel artifacts go in build/kernel.
#
# QEMU is built out-of-tree from ~/workspaces/safe-tee/qemu and its emulator
# binaries are staged in build/qemu.
#
# The VM image is composed with mkosi from image/fedora and embeds both plane
# kernels into the UKI initrd.

.PHONY: kernel kernel-install kernel-clean secure-kernel qemu qemu-install qemu-clean image image-clean

# Build artifacts used as file-based prerequisites for 'image'. Depending on
# these files (not the .PHONY targets) means Make skips them when they already
# exist, so 'make image' does not rebuild the kernel unnecessarily.
KERNEL_BZIMAGE := build/kernel/arch/x86/boot/bzImage
KERNEL_VMLINUX := build/kernel/vmlinux

# --- Kernel (Plane 0 bzImage + Plane 1 vmlinux) -----------------------------
# Phony 'kernel' always delegates to the script; its kbuild step is itself
# incremental (recompiles only changed objects). Run this after editing kernel
# sources to refresh the artifacts.
kernel:
	./scripts/build-kernel.sh build

# File targets: build the kernel only when an artifact is missing. This lets
# 'image' depend on the kernel without forcing a rebuild when it already exists.
# A single kernel build produces both the bzImage and the vmlinux.
$(KERNEL_BZIMAGE) $(KERNEL_VMLINUX):
	./scripts/build-kernel.sh build

kernel-install:
	./scripts/build-kernel.sh install

kernel-clean:
	./scripts/build-kernel.sh clean

# --- Secure kernel (standalone minimal Plane 1 kernel) ----------------------
# Builds a minimal, self-contained secure-plane (Plane 1) kernel from an
# x86_64_defconfig base with an embedded initramfs, via
# components/secure-kernel/build-sk.sh. Artifacts go in
# components/secure-kernel/build-sk (bzImage, vmlinux, vmlinux.bin). This is an
# alternative to reusing the main 'kernel' vmlinux as the plane-1 payload.
secure-kernel:
	./components/secure-kernel/build-sk.sh

# --- QEMU -------------------------------------------------------------------
# Build QEMU out-of-tree; stage emulator binaries in build/qemu.
qemu:
	./scripts/build-qemu.sh build

qemu-install:
	./scripts/build-qemu.sh install

qemu-clean:
	./scripts/build-qemu.sh clean

# --- Image ------------------------------------------------------------------
# Depends on the kernel *artifacts*, so a plain 'make image' rebuilds only the
# image when they already exist (no unnecessary kernel rebuild). To force-
# refresh the kernel first, run 'make kernel image' after changing sources.
image: $(KERNEL_BZIMAGE) $(KERNEL_VMLINUX)
	./scripts/build-image.sh

image-clean:
	./scripts/build-image.sh clean
