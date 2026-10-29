#!/bin/bash
set -euo pipefail

SWTPM_IOCTL="${SWTPM_IOCTL:-swtpm_ioctl}"
DRY_RUN=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] <control-socket>

Shut down the TPM emulator through its control socket, preserving its state.
Stop the VM before using this script on a TPM attached to QEMU.
Environment: SWTPM_IOCTL (default: swtpm_ioctl)
EOF
}

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    usage
    exit 0
fi
if [[ "${1:-}" == --dry-run ]]; then
    DRY_RUN=1
    shift
fi
[[ $# -eq 1 && -n "$1" ]] || { usage >&2; exit 2; }
command -v "$SWTPM_IOCTL" >/dev/null 2>&1 || {
    echo "Executable not found: $SWTPM_IOCTL" >&2
    exit 1
}
command=("$SWTPM_IOCTL" --unix "$1" -s)

if [[ "$DRY_RUN" == 1 ]]; then
    printf '%q ' "${command[@]}"
    printf '\n'
    exit 0
fi

[[ -S "$1" ]] || { echo "TPM control socket not found: $1" >&2; exit 1; }
"${command[@]}"