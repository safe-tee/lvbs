#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMAGE_DIR="$SCRIPT_DIR/../../image/fedora"

PLANE0_DISK="${PLANE0_DISK:-$IMAGE_DIR/fedora-kvm.raw}"
ENABLE_PLANES="${ENABLE_PLANES:-1}"
MEMORY_SIZE="${MEMORY_SIZE:-4G}"
# Plane-0 vCPU count.
SMP="${SMP:-3}"
# Keep total VM vCPU capacity unchanged by default.
# Plane vCPUs are created per plane using existing plane-0 vCPU IDs.
MAXCPUS="${MAXCPUS:-$SMP}"
KERNEL_IRQCHIP_MODE="${KERNEL_IRQCHIP_MODE:-split}"
# Device IRQ destination plane for split irqchip/APIC/MSI routing.
DEVICE_PLANE="${DEVICE_PLANE:-0}"
SERIAL_CONSOLE="-serial mon:stdio"
# Plane 1 secure-plane serial: its earlycon writes to COM2 (I/O 0x2f8), which
# QEMU presents as the second -serial port and we redirect to a dedicated file
# so the secure plane's boot/park output does not interleave with plane 0.
PLANE1_SERIAL_LOG="${PLANE1_SERIAL_LOG:-/tmp/plane1-serial.log}"
if [[ "$ENABLE_PLANES" == "1" ]]; then
    PLANE1_SERIAL="-serial file:$PLANE1_SERIAL_LOG"
else
    PLANE1_SERIAL=""
fi
BIOS="${BIOS:-/usr/share/edk2/ovmf/OVMF_CODE_4M.qcow2}"
OVMF_VARS="${OVMF_VARS:-$SCRIPT_DIR/OVMF_VARS_4M.qcow2}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --disk <path>           Plane 0 disk image path
  --memory <size>         Guest memory size (for example: 2G)
  --smp <count>           vCPU count
  --bios <path>           OVMF firmware path
  --ovmf-vars <path>      OVMF variables file path
  -h, --help              Show this help

Environment variable overrides are also supported:
    PLANE0_DISK ENABLE_PLANES MEMORY_SIZE SMP MAXCPUS KERNEL_IRQCHIP_MODE DEVICE_PLANE BIOS OVMF_VARS PLANE1_SERIAL_LOG
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk)
            [[ $# -ge 2 ]] || {
                echo "Missing value for $1" >&2
                usage
                exit 2
            }
            PLANE0_DISK="$2"
            shift 2
            ;;
        --memory)
            [[ $# -ge 2 ]] || {
                echo "Missing value for $1" >&2
                usage
                exit 2
            }
            MEMORY_SIZE="$2"
            shift 2
            ;;
        --smp)
            [[ $# -ge 2 ]] || {
                echo "Missing value for $1" >&2
                usage
                exit 2
            }
            SMP="$2"
            shift 2
            ;;
        --bios)
            [[ $# -ge 2 ]] || {
                echo "Missing value for $1" >&2
                usage
                exit 2
            }
            BIOS="$2"
            shift 2
            ;;
        --ovmf-vars)
            [[ $# -ge 2 ]] || {
                echo "Missing value for $1" >&2
                usage
                exit 2
            }
            OVMF_VARS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

# Ensure OVMF variables file is present and up to date
"$SCRIPT_DIR/get-firmware-vars.sh"

for required_file in "$PLANE0_DISK" "$BIOS" "$OVMF_VARS"; do
    if [[ ! -f "$required_file" ]]; then
        echo "Missing required file: $required_file" >&2
        exit 1
    fi
done

echo "Launching QEMU with VM planes (UKI secure boot):"
echo "  Disk image:       $PLANE0_DISK"
echo "  OVMF firmware:    $BIOS"
echo "  OVMF variables:   $OVMF_VARS"
echo "  Memory:           $MEMORY_SIZE"
echo "  SMP:              $SMP"
echo "  Kernel irqchip:   $KERNEL_IRQCHIP_MODE"
echo "  Device plane:     $DEVICE_PLANE"
echo "  Planes:           $(if [[ "$ENABLE_PLANES" == "1" ]]; then echo enabled; else echo disabled; fi)"
if [[ "$ENABLE_PLANES" == "1" ]]; then
    echo "  Plane 1 serial:   $PLANE1_SERIAL_LOG"
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "qemu-system-x86_64 was not found in PATH." >&2
    echo "PATH=$PATH" >&2
    exit 127
fi

qemu-system-x86_64 \
    -enable-kvm \
    -machine q35,kernel-irqchip="$KERNEL_IRQCHIP_MODE",device-plane="$DEVICE_PLANE" \
    -cpu host \
    -m "$MEMORY_SIZE" \
    -smp "$SMP",maxcpus="$MAXCPUS" \
    -nographic \
    -drive file="$PLANE0_DISK",format=raw,if=virtio \
    -drive if=pflash,format=qcow2,readonly=on,file="$BIOS" \
    -drive if=pflash,format=qcow2,file="$OVMF_VARS" \
    $SERIAL_CONSOLE \
    $PLANE1_SERIAL
