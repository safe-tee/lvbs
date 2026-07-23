#!/usr/bin/env bash
set -euo pipefail

LOG_TAG="[LVBS-PLANES-VERIFY]"
LOG_FILE="/var/log/lvbs-planes-verify.log"
VTL1_KERNEL="/boot/plane-1/vmlinux"
VTL1_TARGET_PLANE="1"

log_info() {
    echo "$LOG_TAG INFO: $*" | tee -a "$LOG_FILE"
    systemd-cat -t lvbs-planes-verify -p info echo "$*" || true
}

log_error() {
    echo "$LOG_TAG ERROR: $*" | tee -a "$LOG_FILE" >&2
    systemd-cat -t lvbs-planes-verify -p err echo "$*" || true
}

log_success() {
    echo "$LOG_TAG SUCCESS: $*" | tee -a "$LOG_FILE"
    systemd-cat -t lvbs-planes-verify -p info echo "$*" || true
}

mkdir -p /var/log
: > "$LOG_FILE"

log_info "=== Starting VTL0/VTL1 Plane Verification ==="
log_info "Kernel: $(uname -r)"

log_info "Loaded plane configuration:"
log_info "  VTL1 kernel: $VTL1_KERNEL (vmlinux)"
log_info "  VTL1 target plane: $VTL1_TARGET_PLANE"

if [ -f "$VTL1_KERNEL" ]; then
    current_sha="$(sha256sum "$VTL1_KERNEL" | cut -d' ' -f1)"
    log_info "VTL1 SHA256 actual:   $current_sha"
    log_info "VTL1 target plane:    $VTL1_TARGET_PLANE"
    log_success "VTL1 kernel presence verification passed"
    log_info "VTL1 is ready to be loaded by VTL0 and entered in Plane $VTL1_TARGET_PLANE"
else
    log_error "VTL1 kernel missing at $VTL1_KERNEL"
fi

log_info "=== Plane Verification Complete ==="
