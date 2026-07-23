# LVBS out-of-tree build.
#
# The full VBS/HEKI kernel with the KVM VM-planes backend is built for plane 0
# (normal); it boots the compressed bzImage. Kernel artifacts go in build/kernel.
# Plane 1 (secure) boots a separate, standalone minimal secure kernel built by
# components/secure-kernel/build-sk.sh as an uncompressed vmlinux ELF; its
# artifacts go in build/secure-kernel.
#
# QEMU is built out-of-tree from ~/workspaces/safe-tee/qemu and its emulator
# binaries are staged in build/qemu.
#
# The VM image is composed with mkosi from image/fedora and embeds both plane
# kernels into the UKI initrd.

.PHONY: kernel kernel-install kernel-clean secure-kernel secure-kernel-clean qemu qemu-install qemu-clean image image-clean

# Build artifacts used as file-based prerequisites for 'image'. Depending on
# these files (not the .PHONY targets) means Make skips them when they already
# exist, so 'make image' does not rebuild the kernel unnecessarily.
# Plane 0 boots the full VBS kernel bzImage (build/kernel); plane 1 boots the
# standalone secure kernel vmlinux (build/secure-kernel).
KERNEL_BZIMAGE := build/kernel/arch/x86/boot/bzImage
KERNEL_VMLINUX := build/kernel/vmlinux
SK_VMLINUX := build/secure-kernel/vmlinux

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
# components/secure-kernel/build-sk.sh. Artifacts go in build/secure-kernel
# (bzImage, vmlinux, vmlinux.bin), mirroring the main kernel's build/kernel.
# This is an alternative to reusing the main 'kernel' vmlinux as the plane-1
# payload.
secure-kernel:
	./components/secure-kernel/build-sk.sh build

# File target: build the secure kernel only when its vmlinux artifact is
# missing. This lets 'image' depend on the secure kernel (plane 1 payload)
# without forcing a rebuild when it already exists.
$(SK_VMLINUX):
	./components/secure-kernel/build-sk.sh build

# Remove the secure-kernel build artifacts (kbuild output, vmlinux.bin, and the
# compiled static init). Leaves the generated .config in place.
secure-kernel-clean:
	./components/secure-kernel/build-sk.sh clean

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
# image when they already exist (no unnecessary kernel rebuild). Plane 0 uses
# the full VBS kernel bzImage (build/kernel); plane 1 uses the standalone
# secure kernel vmlinux (build/secure-kernel). To force-refresh sources first,
# run 'make kernel secure-kernel image' after changing sources.
image: $(KERNEL_BZIMAGE) $(SK_VMLINUX)
	./scripts/build-image.sh

image-clean:
	./scripts/build-image.sh clean
