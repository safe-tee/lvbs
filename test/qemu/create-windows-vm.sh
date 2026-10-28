#!/bin/bash
set -euo pipefail

QEMU="${QEMU:-qemu-system-x86_64}"
QEMU_IMG="${QEMU_IMG:-qemu-img}"
MEMORY_SIZE="${MEMORY_SIZE:-8G}"
SMP="${SMP:-4}"
BIOS="${BIOS:-/usr/share/edk2/ovmf/OVMF_CODE_4M.qcow2}"
OVMF_VARS_TEMPLATE="${OVMF_VARS_TEMPLATE:-/usr/share/edk2/ovmf/OVMF_VARS_4M.qcow2}"
OVMF_VARS="${OVMF_VARS:-}"
DISPLAY_BACKEND="${QEMU_DISPLAY:-none}"
VNC_DISPLAY="${VNC_DISPLAY:-}"
if [[ -z "$VNC_DISPLAY" && -z "${QEMU_DISPLAY:-}" ]]; then
    VNC_DISPLAY=1
fi
DISK=""
DRY_RUN=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] <windows.vhdx|windows.raw>

Options:
  --disk <path>           Windows disk image (or use the positional argument)
  --memory <size>         Guest memory (default: $MEMORY_SIZE)
  --smp <count>           vCPU count (default: $SMP)
  --bios <path>           OVMF code image
  --vars-template <path>  Initial OVMF variable store
  --ovmf-vars <path>      Persistent writable variable store
    --display <backend>     Use a local display instead of VNC (for example: gtk)
    --vnc <number>         Localhost VNC display (default: 1; TCP port 5901)
  --qemu <path>           VSM-capable QEMU executable
  --dry-run              Print the command without launching or copying NVRAM
  -h, --help             Show this help

Requires KVM planes/VSM host support and QEMU with the hv-vsm CPU property.
Windows must already be installed with UEFI boot and configured for VBS/VSM;
this script does not change Windows policy or enable nested virtualization.
Each disk gets its own persistent NVRAM file unless --ovmf-vars is supplied.
The disk is opened writable; use a copy when testing an existing installation.
VNC listens only on 127.0.0.1. Forward its port over SSH before connecting.

Environment: QEMU QEMU_IMG MEMORY_SIZE SMP BIOS OVMF_VARS_TEMPLATE OVMF_VARS
             QEMU_DISPLAY VNC_DISPLAY
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk|--memory|--smp|--bios|--vars-template|--ovmf-vars|--display|--vnc|--qemu)
            [[ $# -ge 2 && -n "$2" ]] || die "Missing value for $1"
            case "$1" in
                --disk) [[ -z "$DISK" ]] || die "Specify only one disk"; DISK="$2" ;;
                --memory) MEMORY_SIZE="$2" ;;
                --smp) SMP="$2" ;;
                --bios) BIOS="$2" ;;
                --vars-template) OVMF_VARS_TEMPLATE="$2" ;;
                --ovmf-vars) OVMF_VARS="$2" ;;
                --display) DISPLAY_BACKEND="$2"; VNC_DISPLAY="" ;;
                --vnc) VNC_DISPLAY="$2" ;;
                --qemu) QEMU="$2" ;;
            esac
            shift 2
            ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --)
            shift
            [[ $# -eq 1 && -z "$DISK" ]] || die "Specify one disk after --"
            DISK="$1"
            shift
            ;;
        -*) die "Unknown option: $1" ;;
        *)
            [[ -z "$DISK" ]] || die "Specify only one disk"
            DISK="$1"
            shift
            ;;
    esac
done

[[ -n "$DISK" ]] || { usage >&2; exit 2; }
[[ "$SMP" =~ ^[1-9][0-9]*$ ]] || die "--smp must be a positive integer"
if [[ -n "$VNC_DISPLAY" ]]; then
    [[ "$VNC_DISPLAY" =~ ^(0|[1-9][0-9]{0,4})$ ]] &&
        (( VNC_DISPLAY <= 59635 )) || die "--vnc must be a display number from 0 to 59635"
fi
for executable in "$QEMU" "$QEMU_IMG" jq; do
    command -v "$executable" >/dev/null 2>&1 || die "Executable not found: $executable"
done
[[ -r /dev/kvm && -w /dev/kvm ]] || die "/dev/kvm is not accessible"
[[ -f "$DISK" && -r "$DISK" && -w "$DISK" ]] || die "Disk must be readable and writable: $DISK"
DISK="$(realpath -- "$DISK")"
OVMF_VARS="${OVMF_VARS:-${DISK}.nvram.qcow2}"
[[ -r "$BIOS" ]] || die "OVMF code image not found: $BIOS (use --bios)"

cpu_properties="$("$QEMU" -device host-x86_64-cpu,help 2>&1)" || die "Unable to query QEMU CPU properties"
[[ "$cpu_properties" == *hv-vsm* ]] || die "QEMU lacks hv-vsm; build the Windows VSM userspace backend first"

image_format() {
    "$QEMU_IMG" info --output=json "$1" | jq -er '.format'
}

disk_format="$(image_format "$DISK")"
[[ "$disk_format" == raw || "$disk_format" == vhdx ]] || die "Unsupported disk format: $disk_format (expected raw or vhdx)"
bios_format="$(image_format "$BIOS")"
if [[ -e "$OVMF_VARS" ]]; then
    [[ -f "$OVMF_VARS" && -r "$OVMF_VARS" && -w "$OVMF_VARS" ]] || die "NVRAM must be readable and writable: $OVMF_VARS"
    vars_format="$(image_format "$OVMF_VARS")"
else
    [[ -r "$OVMF_VARS_TEMPLATE" ]] || die "OVMF variables template not found: $OVMF_VARS_TEMPLATE"
    vars_format=qcow2
fi
[[ "$bios_format" == raw || "$bios_format" == qcow2 ]] || die "Unsupported OVMF code format: $bios_format"
[[ "$vars_format" == raw || "$vars_format" == qcow2 ]] || die "Unsupported NVRAM format: $vars_format"
[[ "$(realpath -m -- "$OVMF_VARS")" != "$DISK" ]] || die "NVRAM cannot be the Windows disk"
[[ "$(realpath -m -- "$OVMF_VARS")" != "$(realpath -- "$BIOS")" ]] || die "NVRAM cannot be the firmware code image"
[[ "$(realpath -m -- "$OVMF_VARS")" != "$(realpath -m -- "$OVMF_VARS_TEMPLATE")" ]] || die "Use a private NVRAM copy, not the template"

disk_backend="$(jq -cn --arg path "$DISK" --arg format "$disk_format" \
    '{driver: $format, "node-name": "windows-disk", file: {driver: "file", filename: $path}}')"
display_args=(-display "$DISPLAY_BACKEND")
if [[ -n "$VNC_DISPLAY" ]]; then
    display_args=(-display none -vnc "127.0.0.1:$VNC_DISPLAY")
fi
command=(
    "$QEMU"
    -enable-kvm
    -machine q35,kernel-irqchip=split
    -cpu host,hv-relaxed=on,hv-vapic=on,hv-spinlocks=0x1fff,hv-time=on,hv-vpindex=on,hv-runtime=on,hv-synic=on,hv-stimer=on,hv-tlbflush=on,hv-tlbflush-ext=on,hv-ipi=on,hv-vsm=on
    -m "$MEMORY_SIZE"
    -smp "$SMP"
    -blockdev "$disk_backend"
    -device ide-hd,drive=windows-disk,bus=ide.0,bootindex=1
    -drive "if=pflash,unit=0,format=$bios_format,readonly=on,file=${BIOS//,/,,}"
    -drive "if=pflash,unit=1,format=$vars_format,file=${OVMF_VARS//,/,,}"
    -boot menu=on
    -vga std
    "${display_args[@]}"
    -device qemu-xhci
    -device usb-tablet
    -netdev user,id=net0
    -device e1000e,netdev=net0
)

if [[ "$DRY_RUN" == 1 ]]; then
    printf '%q ' "${command[@]}"
    printf '\n'
    exit 0
fi

if [[ ! -e "$OVMF_VARS" ]]; then
    "$QEMU_IMG" convert -O qcow2 "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"
    chmod u+w "$OVMF_VARS"
fi
exec "${command[@]}"