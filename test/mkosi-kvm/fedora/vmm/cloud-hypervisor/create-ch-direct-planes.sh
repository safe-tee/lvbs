#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_DIR="$SCRIPT_DIR/../../../../../image/fedora"

PLANE0_KERNEL="${PLANE0_KERNEL:-$IMAGE_DIR/fedora-kvm.vmlinuz}"
PLANE0_INITRD="${PLANE0_INITRD:-$IMAGE_DIR/fedora-kvm.initrd}"
PLANE0_DISK="${PLANE0_DISK:-$IMAGE_DIR/fedora-kvm.raw}"
PLANE0_BOOT_VCPUS="${PLANE0_BOOT_VCPUS:-2}"
PLANE0_MAX_VCPUS="${PLANE0_MAX_VCPUS:-2}"
ENABLE_PLANE1="${ENABLE_PLANE1:-1}"
SERIAL_LOG_FILE="${SERIAL_LOG_FILE:-/tmp/plane-serial.log}"
PLANE1_SHIM_MAKE_DIR="${PLANE1_SHIM_MAKE_DIR:-$SCRIPT_DIR/../../../build/src/loader}"
PLANE1_SHIM_ELF="${PLANE1_SHIM_ELF:-$PLANE1_SHIM_MAKE_DIR/lvbs-vtl1-pvh-shim.elf}"
PLANE1_PAYLOAD_BIN_DEFAULT="$SCRIPT_DIR/../../kernel/build-sk/vmlinux.bin"
PLANE1_PAYLOAD_BIN="${PLANE1_PAYLOAD_BIN:-$PLANE1_PAYLOAD_BIN_DEFAULT}"
PLANE1_VERIFY_PAYLOAD_MATCH="${PLANE1_VERIFY_PAYLOAD_MATCH:-1}"
ALLOW_CUSTOM_PLANE1_ELF="${ALLOW_CUSTOM_PLANE1_ELF:-0}"
DEPRECATED_PLANE1_KERNEL_BASENAME="lvbs-vtl1-loader.elf"

PLANE1_KERNEL="${PLANE1_KERNEL:-$PLANE1_SHIM_ELF}"
PLANE1_INITRD="${PLANE1_INITRD:-$PLANE0_INITRD}"
PLANE1_BOOT_VCPUS="${PLANE1_BOOT_VCPUS:-1}"
PLANE1_MAX_VCPUS="${PLANE1_MAX_VCPUS:-1}"
PLANE0_CMDLINE_DEFAULT="root=/dev/vda2 console=ttyS0 printk.caller=1"
PLANE0_CMDLINE="${PLANE0_CMDLINE:-$PLANE0_CMDLINE_DEFAULT}"
PLANE1_CMDLINE_DEFAULT="root=/dev/vda2 console=ttyS0 printk.caller=1 plane=1"
PLANE1_CMDLINE="${PLANE1_CMDLINE:-$PLANE1_CMDLINE_DEFAULT}"

for required_file in "$PLANE0_KERNEL" "$PLANE0_INITRD" "$PLANE0_DISK"; do
    if [[ ! -f "$required_file" ]]; then
        echo "Missing required file: $required_file" >&2
        exit 1
    fi
done

if [[ "$ENABLE_PLANE1" == "1" ]]; then
    if [[ "$(basename "$PLANE1_KERNEL")" == "$DEPRECATED_PLANE1_KERNEL_BASENAME" ]]; then
        echo "Deprecated Plane 1 loader selected: $PLANE1_KERNEL" >&2
        echo "Plane 1 must use the prebuilt PVH shim ELF instead: $PLANE1_SHIM_ELF" >&2
        exit 1
    fi

    if [[ "$ALLOW_CUSTOM_PLANE1_ELF" != "1" && "$PLANE1_KERNEL" != "$PLANE1_SHIM_ELF" ]]; then
        echo "Custom Plane 1 ELF is blocked by default: $PLANE1_KERNEL" >&2
        echo "Use the canonical shim path: $PLANE1_SHIM_ELF" >&2
        echo "If you need a custom ELF for debugging, set ALLOW_CUSTOM_PLANE1_ELF=1." >&2
        exit 1
    fi

    for required_file in "$PLANE1_KERNEL" "$PLANE1_INITRD"; do
        if [[ ! -f "$required_file" ]]; then
            echo "Missing required file: $required_file" >&2
            exit 1
        fi
    done

    if [[ "$PLANE1_KERNEL" != *.elf ]]; then
        echo "Unsupported PLANE1_KERNEL format: $PLANE1_KERNEL" >&2
        echo "Plane 1 requires a prebuilt loader ELF. Set PLANE1_KERNEL to $PLANE1_SHIM_ELF or another .elf artifact." >&2
        echo "Tip: build it separately with build-vmlinux-bin-loader.sh, then re-run this launcher." >&2
        exit 1
    fi

    if [[ "$PLANE1_VERIFY_PAYLOAD_MATCH" == "1" ]]; then
        shim_payload_bin="$PLANE1_SHIM_MAKE_DIR/pvh_payload.bin"
        if [[ "$PLANE1_KERNEL" == "$PLANE1_SHIM_ELF" ]]; then
            if [[ ! -f "$shim_payload_bin" ]]; then
                echo "Missing shim payload cache: $shim_payload_bin" >&2
                echo "Rebuild the loader so Plane 1 uses the current payload." >&2
                echo "Command: $SCRIPT_DIR/build-vmlinux-bin-loader.sh \"$PLANE1_PAYLOAD_BIN\" \"$PLANE1_KERNEL\"" >&2
                exit 1
            fi
            if [[ ! -f "$PLANE1_PAYLOAD_BIN" ]]; then
                echo "Expected payload binary not found: $PLANE1_PAYLOAD_BIN" >&2
                echo "Set PLANE1_PAYLOAD_BIN to the kernel payload you embedded into the shim." >&2
                exit 1
            fi
            if ! cmp -s "$shim_payload_bin" "$PLANE1_PAYLOAD_BIN"; then
                echo "Plane 1 shim payload mismatch detected." >&2
                echo "  Embedded payload : $shim_payload_bin" >&2
                echo "  Expected payload : $PLANE1_PAYLOAD_BIN" >&2
                echo "Rebuild the loader so Plane 1 does not reset on stale payload." >&2
                echo "Command: $SCRIPT_DIR/build-vmlinux-bin-loader.sh \"$PLANE1_PAYLOAD_BIN\" \"$PLANE1_KERNEL\"" >&2
                exit 1
            fi
        fi
    fi
fi

kernel_is_compressed_boot_image() {
    local kernel_path="$1"
    local file_output

    file_output="$(file "$kernel_path")"
    [[ "$file_output" == *"Linux kernel x86 boot executable"* && "$file_output" == *"compressed"* ]]
}

if [[ "$ENABLE_PLANE1" == "1" ]]; then
    if kernel_is_compressed_boot_image "$PLANE0_KERNEL" && kernel_is_compressed_boot_image "$PLANE1_KERNEL"; then
        echo "Refusing direct dual-plane boot: both Plane 0 and Plane 1 kernels are compressed boot images." >&2
        echo "Compressed dual boot can make both kernels decompress into the same default region." >&2
        echo "Use serialized VTL0->VTL1 loading with LVBS_VTL1_LOAD_OFFSET." >&2
        exit 1
    fi
fi

if [[ "$PLANE1_CMDLINE" == *,* ]]; then
    echo "Invalid PLANE1_CMDLINE: commas are not supported inside cloud-hypervisor --plane cmdline values" >&2
    echo "Current value: $PLANE1_CMDLINE" >&2
    exit 1
fi

PLANE_ARGS=()
if [[ "$ENABLE_PLANE1" == "1" ]]; then
    PLANE_ARGS+=(--plane "plane_id=1,boot_vcpus=$PLANE1_BOOT_VCPUS,max_vcpus=$PLANE1_MAX_VCPUS,kernel=$PLANE1_KERNEL,initramfs=$PLANE1_INITRD,cmdline=$PLANE1_CMDLINE")
fi

echo "Launching Cloud Hypervisor with VM planes:"
echo "  Plane 0 kernel:   $PLANE0_KERNEL"
echo "  Plane 0 initrd:   $PLANE0_INITRD"
echo "  Plane 0 vcpus:    boot=$PLANE0_BOOT_VCPUS max=$PLANE0_MAX_VCPUS"
if [[ "$ENABLE_PLANE1" == "1" ]]; then
    echo "  Plane 1 kernel:   $PLANE1_KERNEL"
    echo "  Plane 1 initrd:   $PLANE1_INITRD"
    echo "  Plane 1 vcpus:    boot=$PLANE1_BOOT_VCPUS max=$PLANE1_MAX_VCPUS"
else
    echo "  Plane 1:          disabled"
fi
echo "  Serial output:    $SERIAL_LOG_FILE"
echo "  Debug log file:   /tmp/ch-debug.log"

if ! command -v cloud-hypervisor >/dev/null 2>&1; then
    echo "cloud-hypervisor was not found in PATH." >&2
    echo "PATH=$PATH" >&2
    exit 127
fi

cloud-hypervisor \
    -v \
    --log-file /tmp/ch-debug.log \
    --kernel "$PLANE0_KERNEL" \
    --initramfs "$PLANE0_INITRD" \
    --cmdline "$PLANE0_CMDLINE" \
    --disk path="$PLANE0_DISK" \
    --cpus boot="$PLANE0_BOOT_VCPUS",max="$PLANE0_MAX_VCPUS" \
    --memory size=2G \
    --serial file="$SERIAL_LOG_FILE" \
    "${PLANE_ARGS[@]}"

