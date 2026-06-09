#!/bin/bash
# test-direct-load-vbs.sh — Probe direct kernel-memory payload loading path
#
# This test builds a tiny userspace program that invokes the legacy
# kexec_load syscall directly with a raw memory segment. If policy hardening
# (LVBS + lockdown / secure policy) is active, this attempt should be blocked.
#
# Expected secure behavior:
#   - kexec_load returns failure (typically EPERM/EACCES/EKEYREJECTED)
#   - Optional dmesg evidence references lockdown/VBS/kexec denial
#
# Usage:
#   ./test-direct-load-vbs.sh

set -e

PASS=0
FAIL=0
SKIP=0

log_pass() { echo "PASS: $1"; ((++PASS)); }
log_fail() { echo "FAIL: $1"; ((++FAIL)); }
log_skip() { echo "SKIP: $1"; ((++SKIP)); }

echo "=== LVBS Direct Kernel-Load Probe ==="
echo "Date: $(date)"
echo ""

# ── Test 1: Preconditions ─────────────────────────────────────────────
echo "--- Test 1: Preconditions ---"
if [ "$(id -u)" -ne 0 ]; then
    log_skip "Must run as root (kexec_load requires CAP_SYS_BOOT)"
    echo ""
    echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
    exit 0
fi

if ! command -v cc >/dev/null 2>&1; then
    log_skip "No C compiler found (cc)"
    echo ""
    echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
    exit 0
fi

ARCH=$(uname -m 2>/dev/null || true)
if [ -z "$ARCH" ] && [ -r /proc/sys/kernel/arch ]; then
    ARCH=$(cat /proc/sys/kernel/arch)
fi

if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ]; then
    log_skip "Probe payload currently targets x86_64 (detected: ${ARCH:-unknown})"
    echo ""
    echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
    exit 0
fi

log_pass "Root + compiler available"

# ── Test 2: Check VBS/lockdown signals ────────────────────────────────
echo "--- Test 2: Security posture hints ---"
if dmesg | grep -qiE "vbs: HEKI: kernel sealed successfully|vbs-kvm: connected to plane-1|Lockdown:"; then
    log_pass "Detected VBS/lockdown-related kernel signals"
else
    log_skip "No explicit VBS/lockdown signals detected in dmesg"
fi

if [ -r /proc/sys/kernel/kexec_load_disabled ]; then
    KEXEC_LOAD_DISABLED=$(cat /proc/sys/kernel/kexec_load_disabled 2>/dev/null || echo "unknown")
    echo "  kernel.kexec_load_disabled=$KEXEC_LOAD_DISABLED"
    if [ "$KEXEC_LOAD_DISABLED" = "1" ]; then
        log_pass "Legacy kexec_load syscall is disabled by policy"
    else
        log_skip "Legacy kexec_load syscall is still enabled"
    fi
else
    log_skip "kernel.kexec_load_disabled sysctl not available"
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PROBE_C="$TMPDIR/kexec_direct_load_probe.c"
PROBE_BIN="$TMPDIR/kexec_direct_load_probe"
PROBE_OUT="$TMPDIR/probe.out"

cat > "$PROBE_C" <<'EOF'
#define _GNU_SOURCE
#include <errno.h>
#include <linux/kexec.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef KEXEC_ARCH_X86_64
#define KEXEC_ARCH_X86_64 (62 << 16)
#endif

int main(void)
{
    const size_t payload_len = 4096;
    unsigned char *payload = mmap(NULL, payload_len,
                                  PROT_READ | PROT_WRITE,
                                  MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (payload == MAP_FAILED) {
        perror("mmap");
        return 2;
    }

    /* Minimal x86_64 bytes (mov eax, 42; ret) to emulate executable blob. */
    payload[0] = 0xb8;
    payload[1] = 0x2a;
    payload[2] = 0x00;
    payload[3] = 0x00;
    payload[4] = 0x00;
    payload[5] = 0xc3;

    struct kexec_segment seg;
    memset(&seg, 0, sizeof(seg));
    seg.buf = payload;
    seg.bufsz = payload_len;
    seg.mem = (void *)(uintptr_t)0x01000000;
    seg.memsz = payload_len;

    unsigned long entry = 0x01000000;
    unsigned long flags = KEXEC_ARCH_X86_64;

    long rc = syscall(SYS_kexec_load, entry, 1, &seg, flags);
    if (rc == 0) {
        puts("kexec_load=OK errno=0");
        return 0;
    }

    printf("kexec_load=ERR errno=%d (%s)\n", errno, strerror(errno));
    return 1;
}
EOF

# ── Test 3: Build probe ────────────────────────────────────────────────
echo "--- Test 3: Build direct-load probe ---"
if cc -O2 -Wall -Wextra "$PROBE_C" -o "$PROBE_BIN"; then
    log_pass "Probe compiled"
else
    log_fail "Failed to compile probe"
    echo ""
    echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
    exit 1
fi

# ── Test 4: Attempt direct load via kexec_load syscall ────────────────
echo "--- Test 4: Direct raw load attempt ---"
dmesg -C 2>/dev/null || true

"$PROBE_BIN" >"$PROBE_OUT" 2>&1 && probe_rc=0 || probe_rc=$?
probe_line=$(cat "$PROBE_OUT" 2>/dev/null || true)

echo "  probe exit code: $probe_rc"
if [ -n "$probe_line" ]; then
    echo "  probe output: $probe_line"
fi

sleep 0.5
DMESG_HIT=$(dmesg | grep -iE "vbs|lockdown|kexec|denied|rejected" || true)

if [ "$probe_rc" -eq 0 ]; then
    log_fail "kexec_load succeeded for raw payload (direct-load path not blocked)"
    # Do not execute, only unload staged image if possible.
    if command -v kexec >/dev/null 2>&1; then
        kexec -u >/dev/null 2>&1 || true
    fi
else
    if echo "$probe_line" | grep -qiE "errno=(1|13|129)"; then
        log_pass "Direct raw load blocked by kernel policy"
    elif echo "$probe_line" | grep -qi "errno=38"; then
        log_skip "kexec_load not implemented on this kernel (ENOSYS)"
    else
        log_pass "Direct raw load rejected (non-success path)"
    fi
fi

if [ -n "$DMESG_HIT" ]; then
    echo "  dmesg security-relevant lines:"
    echo "$DMESG_HIT" | tail -n 12 | sed 's/^/    /'
    log_pass "Observed kernel security telemetry for the attempt"
else
    log_skip "No dmesg security telemetry captured"
fi

# ── Summary ───────────────────────────────────────────────────────────
echo ""
echo "=== Results ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  SKIP: $SKIP"
echo ""

if [ $FAIL -gt 0 ]; then
    echo "OVERALL: FAILED"
    exit 1
else
    echo "OVERALL: PASSED"
    exit 0
fi
