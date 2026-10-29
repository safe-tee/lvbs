#!/bin/bash
set -euo pipefail

SWTPM="${SWTPM:-swtpm}"
DRY_RUN=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] <state-directory> <control-socket>

Start a TPM 2.0 emulator in the background with persistent state.
Use stop-swtpm.sh <control-socket> to shut it down without deleting state.
Environment: SWTPM (default: swtpm)
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
[[ $# -eq 2 && -n "$1" && -n "$2" ]] || { usage >&2; exit 2; }
command -v "$SWTPM" >/dev/null 2>&1 || { echo "Executable not found: $SWTPM" >&2; exit 1; }

state_dir="$(realpath -m -- "$1")"
control_socket="$(realpath -m -- "$2")"
[[ "$state_dir" != *,* && "$control_socket" != *,* ]] || {
    echo "swtpm paths must not contain commas" >&2
    exit 1
}
command=(
    "$SWTPM" socket --tpm2
    --tpmstate "dir=$state_dir"
    --ctrl "type=unixio,path=$control_socket,mode=0600"
    --daemon
)

if [[ "$DRY_RUN" == 1 ]]; then
    printf '%q ' "${command[@]}"
    printf '\n'
    exit 0
fi

[[ ! -e "$control_socket" && ! -L "$control_socket" ]] || {
    echo "Control socket path already exists: $control_socket" >&2
    exit 1
}
umask 077
mkdir -p -m 700 -- "$state_dir" "$(dirname -- "$control_socket")"
"${command[@]}"