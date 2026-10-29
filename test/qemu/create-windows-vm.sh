#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QEMU="${QEMU:-qemu-system-x86_64}"
QEMU_IMG="${QEMU_IMG:-qemu-img}"
SWTPM="${SWTPM:-swtpm}"
TPM_STATE_DIR="${TPM_STATE_DIR:-}"
MEMORY_SIZE="${MEMORY_SIZE:-8G}"
SMP="${SMP:-4}"
BIOS="${BIOS:-/usr/share/edk2/ovmf/OVMF_CODE_4M.secboot.qcow2}"
OVMF_VARS_TEMPLATE="${OVMF_VARS_TEMPLATE:-/usr/share/edk2/ovmf/OVMF_VARS_4M.secboot.qcow2}"
OVMF_VARS="${OVMF_VARS:-}"
DISPLAY_BACKEND="${QEMU_DISPLAY:-none}"
VNC_DISPLAY="${VNC_DISPLAY:-}"
if [[ -z "$VNC_DISPLAY" && -z "${QEMU_DISPLAY:-}" ]]; then
    VNC_DISPLAY=1
fi
DISK=""
DRY_RUN=0
BOOT_DEBUG_LOG=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] <windows.vhdx|windows.raw>

Options:
  --disk <path>           Windows disk image (or use the positional argument)
  --memory <size>         Guest memory (default: $MEMORY_SIZE)
  --smp <count>           vCPU count (default: $SMP)
    --bios <path>           Secure Boot-capable OVMF code image
    --vars-template <path>  OVMF variable store with enrolled Secure Boot keys
  --ovmf-vars <path>      Persistent writable variable store
    --display <backend>     Use a local display instead of VNC (for example: gtk)
    --vnc <number>         Localhost VNC display (default: 1; TCP port 5901)
  --qemu <path>           VSM-capable QEMU executable
    --swtpm <path>          TPM 2.0 emulator executable (default: $SWTPM)
    --tpm-state <path>      Persistent TPM state directory (default: <disk>.tpm)
    --debug-boot <path>     Log CPU resets/errors and KVM exits; exit on guest reboot
    --dry-run              Print commands without launching or creating VM state
  -h, --help             Show this help

Requires KVM planes/VSM host support and QEMU with the hv-vsm CPU property.
Requires swtpm for the TPM 2.0 device; its state is retained between launches.
Keep the TPM state with the disk and NVRAM, especially when using BitLocker.
Windows must already be installed with UEFI boot and configured for VBS/VSM;
this script does not change Windows policy or enable nested virtualization.
Each disk gets its own persistent NVRAM file unless --ovmf-vars is supplied.
Secure Boot uses enrolled keys and a separate .nvram.secboot.qcow2 store by default.
Custom firmware/NVRAM must also have Secure Boot enabled and Windows signing keys enrolled.
The disk is opened writable; use a copy when testing an existing installation.
VNC listens only on 127.0.0.1. Forward its port over SSH before connecting.

Environment: QEMU QEMU_IMG MEMORY_SIZE SMP BIOS OVMF_VARS_TEMPLATE OVMF_VARS
             QEMU_DISPLAY VNC_DISPLAY SWTPM SWTPM_IOCTL TPM_STATE_DIR
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk|--memory|--smp|--bios|--vars-template|--ovmf-vars|--display|--vnc|--qemu|--swtpm|--tpm-state|--debug-boot)
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
                --swtpm) SWTPM="$2" ;;
                --tpm-state) TPM_STATE_DIR="$2" ;;
                --debug-boot) BOOT_DEBUG_LOG="$2" ;;
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
for executable in "$QEMU" "$QEMU_IMG" "$SWTPM" "${SWTPM_IOCTL:-swtpm_ioctl}" jq flock; do
    command -v "$executable" >/dev/null 2>&1 || die "Executable not found: $executable"
done
[[ -r /dev/kvm && -w /dev/kvm ]] || die "/dev/kvm is not accessible"
[[ -f "$DISK" && -r "$DISK" && -w "$DISK" ]] || die "Disk must be readable and writable: $DISK"
DISK="$(realpath -- "$DISK")"
OVMF_VARS="${OVMF_VARS:-${DISK}.nvram.secboot.qcow2}"
TPM_STATE_DIR="$(realpath -m -- "${TPM_STATE_DIR:-${DISK}.tpm}")"
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
if [[ -n "$BOOT_DEBUG_LOG" ]]; then
    BOOT_DEBUG_LOG="$(realpath -m -- "$BOOT_DEBUG_LOG")"
    for protected_file in "$DISK" "$OVMF_VARS" "$BIOS" "$OVMF_VARS_TEMPLATE"; do
        [[ "$BOOT_DEBUG_LOG" != "$(realpath -m -- "$protected_file")" ]] || die "Boot log cannot overwrite a VM disk or firmware image"
    done
fi

disk_backend="$(jq -cn --arg path "$DISK" --arg format "$disk_format" \
    '{driver: $format, "node-name": "windows-disk", file: {driver: "file", filename: $path}}')"
display_args=(-display "$DISPLAY_BACKEND")
if [[ -n "$VNC_DISPLAY" ]]; then
    display_args=(-display none -vnc "127.0.0.1:$VNC_DISPLAY")
fi
tpm_runtime_dir="${TMPDIR:-/tmp}/windows-vtpm.DRYRUN"
if [[ "$DRY_RUN" != 1 ]]; then
    tpm_runtime_dir="$(mktemp -d "${TMPDIR:-/tmp}/windows-vtpm.XXXXXXXX")"
fi
swtpm_command=(
    env "SWTPM=$SWTPM" bash "$SCRIPT_DIR/start-swtpm.sh"
    "$TPM_STATE_DIR" "$tpm_runtime_dir/control.sock"
)
command=(
    "$QEMU"
    -enable-kvm
    -machine q35,kernel-irqchip=split,smm=on
    -global driver=cfi.pflash01,property=secure,value=on
    -cpu host,hv-relaxed=on,hv-vapic=on,hv-avic=on,hv-spinlocks=0x1fff,hv-time=on,hv-vpindex=on,hv-runtime=on,hv-synic=on,hv-stimer=on,hv-tlbflush=on,hv-tlbflush-ext=on,hv-ipi=on,hv-vsm=on
    -m "$MEMORY_SIZE"
    -smp "$SMP"
    -chardev "socket,id=chrtpm,path=${tpm_runtime_dir//,/,,}/control.sock"
    -tpmdev emulator,id=tpm0,chardev=chrtpm
    -device tpm-crb,tpmdev=tpm0
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
if [[ -n "$BOOT_DEBUG_LOG" ]]; then
    command+=(
        -no-reboot -d cpu_reset,guest_errors -D "$BOOT_DEBUG_LOG"
        -trace enable=kvm_run_exit
        -trace enable=kvm_run_exit_system_event
    )
fi

if [[ "$DRY_RUN" == 1 ]]; then
    printf '%q ' "${swtpm_command[@]}"
    printf '\n'
    printf '%q ' "${command[@]}"
    printf '\n'
    exit 0
fi

cleanup() {
    if [[ -S "$tpm_runtime_dir/control.sock" ]]; then
        bash "$SCRIPT_DIR/stop-swtpm.sh" "$tpm_runtime_dir/control.sock" || true
    fi
    rm -rf -- "$tpm_runtime_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -m 700 -- "$TPM_STATE_DIR"
exec {tpm_lock_fd}>"$TPM_STATE_DIR/.lock"
flock -n "$tpm_lock_fd" || die "TPM state is already in use: $TPM_STATE_DIR"
"${swtpm_command[@]}"

if [[ ! -e "$OVMF_VARS" ]]; then
    "$QEMU_IMG" convert -O qcow2 "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"
    chmod u+w "$OVMF_VARS"
fi
"${command[@]}"