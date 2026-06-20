#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LINUX_SRC_ROOT_DEFAULT="$HOME/workspaces/linux"
LINUX_SRC_ROOT="${LINUX_SRC_ROOT:-$LINUX_SRC_ROOT_DEFAULT}"

VTL0_BUILD_DIR_DEFAULT="$SCRIPT_DIR/../../../kernel/build"
VTL1_BUILD_DIR_DEFAULT="$SCRIPT_DIR/../../../kernel/build-sk"
VTL0_BUILD_DIR="${VTL0_BUILD_DIR:-$VTL0_BUILD_DIR_DEFAULT}"
VTL1_BUILD_DIR="${VTL1_BUILD_DIR:-$VTL1_BUILD_DIR_DEFAULT}"

# VTL0 uses a compressed bzImage, VTL1 uses an uncompressed vmlinux payload.
VTL0_KERNEL_SRC_DEFAULT="$VTL0_BUILD_DIR/arch/x86/boot/bzImage"
VTL1_KERNEL_SRC_DEFAULT="$VTL1_BUILD_DIR/vmlinux"
VTL0_KERNEL_SRC="${VTL0_KERNEL_SRC:-$VTL0_KERNEL_SRC_DEFAULT}"
VTL1_KERNEL_SRC="${VTL1_KERNEL_SRC:-$VTL1_KERNEL_SRC_DEFAULT}"

# Physical base where plane 1 (VTL1) RAM is carved out of plane 0's RAM
# (Windows-VBS / VTL model).  The region [LOAD_OFFSET, LOAD_OFFSET+MEMORY_SIZE)
# is reserved from plane 0 via a matching memmap= on the plane-0 kernel command
# line (see finalize-image.sh.chroot) so plane 0 never allocates there and the
# secure plane owns it exclusively.  Constraints:
#   - Must stay < 4GB (QEMU builds a 4GB identity map for the plane).
#   - Must clear plane-0's low <1MB real-mode trampoline.
#   - Must match the memmap= reservation on the plane-0 cmdline.
#   - Must end BELOW the firmware ACPI tables that OVMF places at the top of
#     plane-0's low (<4GB) RAM block (~0x7fb6d000 with -m 4G), so the memmap
#     reservation does not steal them from plane 0.  0x40000000 + 0x3c000000 =
#     0x7c000000 leaves the top 64MB of the 2GB block (ACPI/NVS/reserved) to
#     plane 0.
# (A later step has the secure plane additionally seal this exact range in
# plane 0's EPT.)
VTL1_LOAD_OFFSET_DEFAULT="0x40000000"
VTL1_LOAD_OFFSET="${VTL1_LOAD_OFFSET:-$VTL1_LOAD_OFFSET_DEFAULT}"

# Verified VTL1 execution must enter Plane 1.
VTL1_TARGET_PLANE_DEFAULT="1"
VTL1_TARGET_PLANE="${VTL1_TARGET_PLANE:-$VTL1_TARGET_PLANE_DEFAULT}"
VTL1_MEMORY_SIZE_DEFAULT="0x3c000000"
VTL1_MEMORY_SIZE="${VTL1_MEMORY_SIZE:-$VTL1_MEMORY_SIZE_DEFAULT}"
# secure_monitor activates the in-kernel secure-plane monitor (drivers/virt/
# secure_monitor.c): its late_initcall spawns the "vbs-secmon" kthread which
# immediately issues KVM_HC_VBS_VTL_RETURN to park the secure plane and hand
# control back to plane 0.  Without it the secure kernel never parks, and
# instead boots on toward rdinit=/init and hangs.  This is decoupled from the
# full VBS/HEKI stack, so plane 1 can be any kernel (or an SVSM) that honours
# the VTL return handshake.
#
# IMPORTANT: the secure plane gets no periodic timer tick, so jiffies never
# advance there.  The full 8250 serial driver's port autoconfig does a
# jiffies-based busy wait and therefore spins forever (hang right after
# "Serial: 8250/16550 driver", before late_initcall, so secure_monitor never
# runs).
# Work around it by disabling the 8250 ports (8250.nr_uarts=0) and keeping the
# pure-polled earlycon as the console (drop console=ttyS0, add keep_bootcon) so
# output survives all the way to the park.  This is a bring-up workaround; a
# real secure plane needs either a working plane timer or a timer-free payload
# (SVSM).
#
# SERIAL SEPARATION: plane 1 earlycon is pointed at COM2 (I/O 0x2f8) instead of
# the shared COM1 (0x3f8).  The QEMU launch script wires COM2 to a dedicated
# file (/tmp/plane1-serial.log) so the secure plane's boot/park output lands in
# its own log rather than interleaving with plane 0 on stdio.
VTL1_CMDLINE_DEFAULT="earlycon=uart8250,io,0x2f8,115200n8 keep_bootcon loglevel=7 maxcpus=1 noefi 8250.nr_uarts=0 secure_monitor rdinit=/init panic=1"
# Plane 1 cmdline is sealed into config-vm-planes (inside the UKI initrd).
# Keep this build-time constant here so there is no runtime override path.
VTL1_CMDLINE="$VTL1_CMDLINE_DEFAULT"

VTL1_INITRD_DEST_REL="boot/plane-${VTL1_TARGET_PLANE}/vmlinux"
CONFIG_VM_PLANES_REL="config-vm-planes"
DRACUT_CONF_REL="etc/dracut.conf.d/50-lvbs-vtl1.conf"
MKOSI_EXTRA_DIR="$SCRIPT_DIR/mkosi.extra"

if ! command -v mkosi >/dev/null 2>&1; then
	echo "Error: mkosi is not installed or not in PATH"
	echo "Install it first, then re-run this script."
	exit 1
fi

if [ ! -d "$LINUX_SRC_ROOT" ]; then
	echo "Error: Linux source root not found: $LINUX_SRC_ROOT"
	echo "Set LINUX_SRC_ROOT and re-run."
	exit 1
fi

if [ ! -f "$VTL0_KERNEL_SRC" ]; then
	echo "Error: VTL0 kernel not found: $VTL0_KERNEL_SRC"
	exit 1
fi

if [ ! -f "$VTL1_KERNEL_SRC" ]; then
	echo "Error: VTL1 kernel not found: $VTL1_KERNEL_SRC"
	exit 1
fi

VTL0_KREL="$(make -s -C "$LINUX_SRC_ROOT" O="$VTL0_BUILD_DIR" kernelrelease)"
VTL1_KREL="$(make -s -C "$LINUX_SRC_ROOT" O="$VTL1_BUILD_DIR" kernelrelease)"

# Only clear generated plane artifacts so static files under mkosi.extra survive.
rm -rf "$MKOSI_EXTRA_DIR/usr/lib/lvbs"
rm -rf "$MKOSI_EXTRA_DIR/usr/lib/modules"
rm -rf "$MKOSI_EXTRA_DIR/boot/plane-${VTL1_TARGET_PLANE}"
rm -f "$MKOSI_EXTRA_DIR/$CONFIG_VM_PLANES_REL"
rm -f "$MKOSI_EXTRA_DIR/etc/lvbs/config-vm-planes"
rm -f "$MKOSI_EXTRA_DIR/$DRACUT_CONF_REL"

mkdir -p "$(dirname "$MKOSI_EXTRA_DIR/$VTL1_INITRD_DEST_REL")"
mkdir -p "$(dirname "$MKOSI_EXTRA_DIR/$CONFIG_VM_PLANES_REL")"
mkdir -p "$(dirname "$MKOSI_EXTRA_DIR/$DRACUT_CONF_REL")"

cp -f "$VTL1_KERNEL_SRC" "$MKOSI_EXTRA_DIR/$VTL1_INITRD_DEST_REL"

echo "Installing VTL0 kernel modules into mkosi.extra for UKI initrd generation..."
make -s -C "$LINUX_SRC_ROOT" O="$VTL0_BUILD_DIR" \
	INSTALL_MOD_PATH="$MKOSI_EXTRA_DIR/usr" \
	INSTALL_MOD_STRIP=1 \
	modules_install

# Drop source/build symlinks from the staged tree; they are not needed in-image.
rm -f "$MKOSI_EXTRA_DIR/usr/lib/modules/$VTL0_KREL/build"
rm -f "$MKOSI_EXTRA_DIR/usr/lib/modules/$VTL0_KREL/source"

# Prune staged modules to only KVM-essential drivers to keep initrd small.
# Without this, the full module tree (~580 MB) bloats the UKI beyond what
# OVMF can load into guest RAM.
MODULES_KERNEL_DIR="$MKOSI_EXTRA_DIR/usr/lib/modules/$VTL0_KREL/kernel"
KEEP_MODULES_TMP="$(mktemp -d)"

for mod in \
	drivers/virtio \
	drivers/block/virtio_blk.ko \
	drivers/scsi/virtio_scsi.ko \
	drivers/net/virtio_net.ko \
	drivers/char/virtio_console.ko \
	drivers/ata/ahci.ko \
	drivers/ata/libahci.ko \
	drivers/ata/ata_piix.ko \
	drivers/ata/libata.ko \
	drivers/scsi/sd_mod.ko \
	drivers/scsi/scsi_mod.ko \
	drivers/net/ethernet/intel/e1000 \
	drivers/net/ethernet/intel/e1000e \
	fs/ext4 \
	fs/fat \
	fs/vfat \
	fs/xfs \
	fs/jbd2 \
	fs/nls \
; do
	src="$MODULES_KERNEL_DIR/$mod"
	if [ -e "$src" ]; then
		dest="$KEEP_MODULES_TMP/$mod"
		mkdir -p "$(dirname "$dest")"
		cp -a "$src" "$dest"
	fi
done

rm -rf "$MODULES_KERNEL_DIR"
mkdir -p "$MODULES_KERNEL_DIR"
cp -a "$KEEP_MODULES_TMP"/. "$MODULES_KERNEL_DIR"/
rm -rf "$KEEP_MODULES_TMP"

# Regenerate module dependency files after pruning.
depmod -b "$MKOSI_EXTRA_DIR/usr" "$VTL0_KREL" 2>/dev/null || true

echo "Pruned module tree to $(du -sh "$MODULES_KERNEL_DIR" | cut -f1)"

# Ensure kernel-install/ukify uses the custom VTL0 kernel image.
VTL0_MODULES_DIR="$MKOSI_EXTRA_DIR/usr/lib/modules/$VTL0_KREL"
mkdir -p "$VTL0_MODULES_DIR"
cp -f "$VTL0_KERNEL_SRC" "$VTL0_MODULES_DIR/vmlinuz"

VTL0_SHA256="$(sha256sum "$VTL0_KERNEL_SRC" | cut -d' ' -f1)"
VTL1_SHA256="$(sha256sum "$MKOSI_EXTRA_DIR/$VTL1_INITRD_DEST_REL" | cut -d' ' -f1)"

cat > "$MKOSI_EXTRA_DIR/$CONFIG_VM_PLANES_REL" <<EOF
# VM Planes configuration consumed by linux/init/vm_planes.c
PLANE_COUNT=2
PLANE_${VTL1_TARGET_PLANE}_LOAD_OFFSET=$VTL1_LOAD_OFFSET
PLANE_${VTL1_TARGET_PLANE}_MEMORY_SIZE=$VTL1_MEMORY_SIZE
PLANE_${VTL1_TARGET_PLANE}_KERNEL=/$VTL1_INITRD_DEST_REL
PLANE_${VTL1_TARGET_PLANE}_KERNEL_FORMAT=elf
PLANE_${VTL1_TARGET_PLANE}_CMDLINE="$VTL1_CMDLINE"
EOF

cat > "$MKOSI_EXTRA_DIR/$DRACUT_CONF_REL" <<EOF
# Embed the secure-plane kernel payload and VM planes config into the initrd.
install_items+=" /$VTL1_INITRD_DEST_REL /$CONFIG_VM_PLANES_REL "
# Only include modules needed for a KVM guest — keeps initrd small.
hostonly="no"
add_dracutmodules+=" kernel-modules base rootfs-block "
omit_dracutmodules+=" plymouth multipath iscsi nfs cifs nbd dmraid mdraid "
filesystems+=" ext4 vfat xfs "
drivers+=" virtio virtio_pci virtio_blk virtio_scsi virtio_net virtio_console "
drivers+=" sd_mod ahci ata_piix e1000 e1000e "
EOF

echo "[INSTRUMENTATION] Kernel verification details:"
echo "[INSTRUMENTATION] VTL0 kernel (compressed bzImage):"
echo "[INSTRUMENTATION]   Source: $VTL0_KERNEL_SRC"
echo "[INSTRUMENTATION]   Size: $(stat -c%s "$VTL0_KERNEL_SRC") bytes"
echo "[INSTRUMENTATION]   SHA256: $VTL0_SHA256"
echo "[INSTRUMENTATION] VTL1 kernel (uncompressed vmlinux):"
echo "[INSTRUMENTATION]   Source: $VTL1_KERNEL_SRC"
echo "[INSTRUMENTATION]   Initrd path: /$VTL1_INITRD_DEST_REL"
echo "[INSTRUMENTATION]   Size: $(stat -c%s "$MKOSI_EXTRA_DIR/$VTL1_INITRD_DEST_REL") bytes"
echo "[INSTRUMENTATION]   SHA256: $VTL1_SHA256"
echo "[INSTRUMENTATION]   Target plane: $VTL1_TARGET_PLANE"
echo "[INSTRUMENTATION]   Load offset: $VTL1_LOAD_OFFSET"

echo "[INSTRUMENTATION] config-vm-planes generated:"
cat "$MKOSI_EXTRA_DIR/$CONFIG_VM_PLANES_REL"

echo ""
echo "========== KERNEL STAGING SUMMARY =========="
echo "Staged kernels for image build:"
echo "  VTL0 source kernel (Plane 0 - compressed bzImage): $VTL0_KERNEL_SRC"
echo "  VTL1 source kernel (Plane 1 - uncompressed vmlinux): $VTL1_KERNEL_SRC"
echo "  VTL1 staged for initrd: $VTL1_KERNEL_SRC -> /$VTL1_INITRD_DEST_REL"
echo "    Target plane: $VTL1_TARGET_PLANE"
echo "    Load offset: $VTL1_LOAD_OFFSET"
echo "    Memory size: $VTL1_MEMORY_SIZE"
echo "    cmdline: $VTL1_CMDLINE"
echo "  VTL0 kernelrelease: $VTL0_KREL"
echo "  VTL1 kernelrelease: $VTL1_KREL"
echo "  VTL0 SHA256: $VTL0_SHA256"
echo "  VTL1 SHA256: $VTL1_SHA256"
echo ""
echo "[INSTRUMENTATION] Dracut configuration for VTL1 embedding:"
cat "$MKOSI_EXTRA_DIR/$DRACUT_CONF_REL"
echo ""
echo "Building vm-planes initrd cpio with config and kernel payload..."
VM_PLANES_INITRD="$SCRIPT_DIR/vm-planes-initrd.cpio"
VM_PLANES_INITRD_STAGING="$(mktemp -d)"
mkdir -p "$VM_PLANES_INITRD_STAGING/boot/plane-${VTL1_TARGET_PLANE}"
cp -f "$MKOSI_EXTRA_DIR/$CONFIG_VM_PLANES_REL" "$VM_PLANES_INITRD_STAGING/$CONFIG_VM_PLANES_REL"
cp -f "$MKOSI_EXTRA_DIR/$VTL1_INITRD_DEST_REL" "$VM_PLANES_INITRD_STAGING/$VTL1_INITRD_DEST_REL"
(cd "$VM_PLANES_INITRD_STAGING" && find . | cpio -o -H newc) > "$VM_PLANES_INITRD"
rm -rf "$VM_PLANES_INITRD_STAGING"
echo "  Created $VM_PLANES_INITRD ($(du -sh "$VM_PLANES_INITRD" | cut -f1))"

echo ""
echo "Building fedora-kvm.raw with mkosi..."
(
	cd "$SCRIPT_DIR"
	mkosi --force build
)

echo ""
echo "========== BUILD COMPLETE =========="
echo "Build complete: $SCRIPT_DIR/fedora-kvm.raw"
echo "Plane kernel payloads embedded in initrd:"
echo "  /$VTL1_INITRD_DEST_REL (VTL1 / Plane 1 - uncompressed)"
echo ""
echo "EXPECTED BOOT FLOW:"
echo "  1. UEFI firmware -> systemd-stub (UKI with VTL0 bzImage kernel)"
echo "  2. VTL0 kernel + initrd boot"
echo "  3. Initrd contains embedded VTL1 uncompressed vmlinux (/$VTL1_INITRD_DEST_REL)"
echo "     and VM planes config (/$CONFIG_VM_PLANES_REL)"
echo "  4. VTL0 init should verify VTL1 kernel SHA256: $VTL1_SHA256"
echo "  5. VTL0 init should load VTL1 kernel at offset $VTL1_LOAD_OFFSET"
echo "  6. VTL0 init should place the verified VTL1 kernel into Plane $VTL1_TARGET_PLANE"
echo "  7. VTL0 init should launch the Plane $VTL1_TARGET_PLANE kernel via hypercall"
echo ""
echo "VERIFICATION: Check /config-vm-planes inside the initrd for plane configuration"
