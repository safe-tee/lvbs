#!/bin/bash

SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
. "$SCRIPTS_DIR/common.sh"

BUILD_ROOT="$SCRIPTS_DIR/build-sk"
mkdir -p "$BUILD_ROOT"

if [ ! -f "$BUILD_ROOT/.config" ]; then
	make -C $LINUX_SRC_ROOT O="$BUILD_ROOT" x86_64_defconfig
fi

if ! grep -q '^CONFIG_X86_64=y$' "$BUILD_ROOT/.config"; then
	echo "[build-sk] Existing config is not x86_64; regenerating x86_64_defconfig"
	make -C $LINUX_SRC_ROOT O="$BUILD_ROOT" x86_64_defconfig
fi

set_kconfig_bool() {
	local key="$1"
	local value="$2"
	sed -i \
		-e "/^${key}=.*/d" \
		-e "/^# ${key} is not set/d" \
		"$BUILD_ROOT/.config"
	echo "${key}=${value}" >> "$BUILD_ROOT/.config"
}

# Ensure 64-bit x86 architecture (disable 32-bit, enable 64-bit)
set_kconfig_bool CONFIG_X86_32 n
set_kconfig_bool CONFIG_X86_64 y
set_kconfig_bool CONFIG_64BIT y

# Plane 1 needs guest/paravirt boot support; otherwise CH can reset-loop Plane 1.
set_kconfig_bool CONFIG_HYPERVISOR_GUEST y
set_kconfig_bool CONFIG_PARAVIRT y
set_kconfig_bool CONFIG_KVM_GUEST y
set_kconfig_bool CONFIG_PVH y
set_kconfig_bool CONFIG_XEN_PVH y

# Embed a minimal initramfs so Plane 1 can boot without an external rootfs.
# The initramfs contains a statically linked /init that keeps the kernel running.
INITRAMFS_DIR="$SCRIPTS_DIR/initramfs-sk"
mkdir -p "$INITRAMFS_DIR"/{dev,proc,sys}

# Build a static init binary (no libc dependency)
gcc -nostdlib -static -o "$INITRAMFS_DIR/init" "$INITRAMFS_DIR/init.c"
if [ $? -ne 0 ]; then
    echo "[build-sk] Failed to compile static init"
    exit 1
fi

set_kconfig_bool CONFIG_BLK_DEV_INITRD y
sed -i \
    -e '/^CONFIG_INITRAMFS_SOURCE=.*/d' \
    "$BUILD_ROOT/.config"
echo "CONFIG_INITRAMFS_SOURCE=\"$INITRAMFS_DIR\"" >> "$BUILD_ROOT/.config"

# Enable SMP so CALL_FUNCTION_VECTOR (0xfc) IDT handler is compiled in.
# Without it, cross-plane interrupts at vector 0xfc hit the spurious handler.
# The plane cmdline uses maxcpus=1 to boot with only the BSP.
set_kconfig_bool CONFIG_SMP y

# ─── KVM VM-planes secure-plane (plane 1) monitor support ───
# This secure kernel runs as plane 1.  It must hand control back to the
# normal plane (plane 0) via the KVM_HC_VBS_VTL_RETURN hypercall and then
# service VTL calls.  CONFIG_VBS_SECURE_MONITOR provides that in-kernel
# handshake WITHOUT pulling in the full VBS/HEKI stack.  It is activated by
# the "secure_monitor" kernel command-line option (see build-vm-planes-image.sh).
set_kconfig_bool CONFIG_VIRT_DRIVERS y
set_kconfig_bool CONFIG_VBS_SECURE_MONITOR y

# ─── Strip unnecessary drivers/subsystems ───
# The secure kernel runs a minimal initramfs with no hardware interaction
# beyond the serial console and KVM paravirt clock.

# Graphics / Display
set_kconfig_bool CONFIG_DRM n
set_kconfig_bool CONFIG_AGP n
set_kconfig_bool CONFIG_VGA_ARB n
set_kconfig_bool CONFIG_FB n

# Sound
set_kconfig_bool CONFIG_SOUND n

# USB
set_kconfig_bool CONFIG_USB_SUPPORT n

# HID / Input devices
set_kconfig_bool CONFIG_HID n
set_kconfig_bool CONFIG_INPUT_MOUSE n
set_kconfig_bool CONFIG_INPUT_KEYBOARD n
set_kconfig_bool CONFIG_INPUT_JOYSTICK n
set_kconfig_bool CONFIG_INPUT_TOUCHSCREEN n
set_kconfig_bool CONFIG_INPUT_TABLET n
set_kconfig_bool CONFIG_SERIO n
set_kconfig_bool CONFIG_GAMEPORT n

# Network drivers (keep NET core for potential future use)
set_kconfig_bool CONFIG_ETHERNET n
set_kconfig_bool CONFIG_WLAN n
set_kconfig_bool CONFIG_WIRELESS n
set_kconfig_bool CONFIG_MAC80211 n
set_kconfig_bool CONFIG_CFG80211 n
set_kconfig_bool CONFIG_NETFILTER n

# Filesystems (built-in initramfs only, no block-based fs needed)
set_kconfig_bool CONFIG_EXT4_FS n
set_kconfig_bool CONFIG_EXT2_FS n
set_kconfig_bool CONFIG_FAT_FS n
set_kconfig_bool CONFIG_VFAT_FS n
set_kconfig_bool CONFIG_MSDOS_FS n
set_kconfig_bool CONFIG_ISOFS n
set_kconfig_bool CONFIG_NFS_FS n
set_kconfig_bool CONFIG_NFSD n
set_kconfig_bool CONFIG_LOCKD n
set_kconfig_bool CONFIG_SUNRPC n
set_kconfig_bool CONFIG_9P_FS n
set_kconfig_bool CONFIG_CIFS n
set_kconfig_bool CONFIG_FUSE_FS n

# Storage / Block devices
set_kconfig_bool CONFIG_ATA n
set_kconfig_bool CONFIG_SCSI n
set_kconfig_bool CONFIG_MD n
set_kconfig_bool CONFIG_BLK_DEV_LOOP n
set_kconfig_bool CONFIG_BLK_DEV_NBD n
set_kconfig_bool CONFIG_NVME_CORE n

# Misc hardware
set_kconfig_bool CONFIG_PCI n
set_kconfig_bool CONFIG_PCCARD n
set_kconfig_bool CONFIG_I2C n
set_kconfig_bool CONFIG_SPI n
set_kconfig_bool CONFIG_HWMON n
set_kconfig_bool CONFIG_THERMAL n
set_kconfig_bool CONFIG_WATCHDOG n
set_kconfig_bool CONFIG_LEDS_CLASS n
set_kconfig_bool CONFIG_NEW_LEDS n
set_kconfig_bool CONFIG_ACCESSIBILITY n
set_kconfig_bool CONFIG_IOMMU_SUPPORT n
set_kconfig_bool CONFIG_VHOST_NET n
set_kconfig_bool CONFIG_VIRTIO_PCI n
set_kconfig_bool CONFIG_VIRTIO_BALLOON n
set_kconfig_bool CONFIG_PTP_1588_CLOCK n
set_kconfig_bool CONFIG_PPS n
set_kconfig_bool CONFIG_CRYPTO_HW n
set_kconfig_bool CONFIG_POWER_SUPPLY n

# Set physical start to match the plane's load_offset + kernel offset.
# The kernel loads at load_offset + CONFIG_PHYSICAL_START.
sed -i \
    -e '/^CONFIG_PHYSICAL_START=.*/d' \
    "$BUILD_ROOT/.config"
echo "CONFIG_PHYSICAL_START=0x1000000" >> "$BUILD_ROOT/.config"
sed -i \
    -e '/^CONFIG_PHYSICAL_ALIGN=.*/d' \
    "$BUILD_ROOT/.config"
echo "CONFIG_PHYSICAL_ALIGN=0x1000000" >> "$BUILD_ROOT/.config"

make -C $LINUX_SRC_ROOT O="$BUILD_ROOT" olddefconfig

make -C $LINUX_SRC_ROOT O="$BUILD_ROOT" -j$(nproc)
make -C $LINUX_SRC_ROOT O="$BUILD_ROOT" -j$(nproc) modules
objcopy -O binary -R .note -R .comment -S "$BUILD_ROOT/vmlinux" "$BUILD_ROOT/vmlinux.bin"
