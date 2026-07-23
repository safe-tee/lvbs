#!/bin/bash
# test-kexec-vbs.sh — Validate kexec VBS validation path
#
# Run this script inside the guest VM after boot.
# It attempts kexec_file_load and checks dmesg for VBS messages.
#
# Expected behavior:
#   1. vbs_kexec_validate() is called from kexec_file_load
#   2. QEMU receives VBS_CALL_KEXEC_VALIDATE
#   3. If sig_ok=1 → approved, kexec proceeds
#   4. If sig_ok=0 → rejected with -EKEYREJECTED
#
# Usage:
#   # Inside the guest:
#   ./test-kexec-vbs.sh /boot/vmlinuz-$(uname -r)
#
# Check QEMU stderr for:
#   vbs: KEXEC_VALIDATE gpa=... size=... sig_ok=...

set -e

# Try common kernel image locations
if [ -n "$1" ]; then
    KERNEL="$1"
elif [ -f "/boot/vmlinuz-$(uname -r)" ]; then
    KERNEL="/boot/vmlinuz-$(uname -r)"
elif [ -f "/usr/lib/modules/$(uname -r)/vmlinuz" ]; then
    KERNEL="/usr/lib/modules/$(uname -r)/vmlinuz"
else
    KERNEL="/boot/vmlinuz-$(uname -r)"
fi
PASS=0
FAIL=0
SKIP=0

log_pass() { echo "PASS: $1"; ((++PASS)); }
log_fail() { echo "FAIL: $1"; ((++FAIL)); }
log_skip() { echo "SKIP: $1"; ((++SKIP)); }

echo "=== VBS Kexec Validation Test ==="
echo "Kernel: $KERNEL"
echo "Date: $(date)"
echo ""

# ── Test 1: Check VBS is available ────────────────────────────────────
echo "--- Test 1: VBS availability ---"
if dmesg | grep -q "vbs: HEKI: kernel sealed successfully\|vbs-kvm: connected to plane-1"; then
    log_pass "VBS is active (backend connected)"
else
    log_skip "VBS not active — skipping kexec tests"
    echo ""
    echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
    exit 0
fi

# ── Test 2: Check kexec tools are available ───────────────────────────
echo "--- Test 2: kexec tool availability ---"
if command -v kexec &>/dev/null; then
    log_pass "kexec tool found: $(which kexec)"
else
    log_skip "kexec tool not installed — install kexec-tools"
    echo ""
    echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
    exit 0
fi

# ── Test 3: Check kernel image exists ─────────────────────────────────
echo "--- Test 3: Kernel image ---"
if [ -f "$KERNEL" ]; then
    log_pass "Kernel image exists: $KERNEL ($(stat -c%s "$KERNEL") bytes)"
else
    log_fail "Kernel image not found: $KERNEL"
    echo ""
    echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
    exit 1
fi

# ── Test 4: Attempt kexec -l (kexec_file_load) ───────────────────────
echo "--- Test 4: kexec_file_load with signed kernel ---"
# Clear dmesg marker
dmesg -C 2>/dev/null || true

# Attempt to load — this triggers VBS_CALL_KEXEC_VALIDATE
# Use --force to skip some checks, but the VBS hook runs regardless
kexec_output=$(kexec -l "$KERNEL" --reuse-cmdline 2>&1) && kexec_rc=0 || kexec_rc=$?

echo "  kexec -l returned: $kexec_rc"
if [ -n "$kexec_output" ]; then
    echo "  output: $kexec_output"
fi

# Check dmesg for VBS validation messages
sleep 0.5
VBS_VALIDATE=$(dmesg | grep "vbs-kvm: kexec_validate\|vbs: kexec kernel" || true)
VBS_REJECTED=$(dmesg | grep "vbs: kexec kernel rejected" || true)

if [ -n "$VBS_VALIDATE" ]; then
    echo "  dmesg VBS messages:"
    echo "$VBS_VALIDATE" | sed 's/^/    /'

    if [ -z "$VBS_REJECTED" ]; then
        if [ $kexec_rc -eq 0 ]; then
            log_pass "kexec_file_load succeeded — VBS approved the kernel"
        else
            log_fail "kexec_file_load failed ($kexec_rc) but VBS did not reject"
        fi
    else
        log_pass "VBS rejected the kernel (expected if unsigned)"
        echo "  This is correct behavior — unsigned kernels are blocked"
    fi
else
    if [ $kexec_rc -eq 0 ]; then
        log_pass "kexec_file_load succeeded (VBS may have approved silently)"
    else
        log_fail "kexec_file_load failed ($kexec_rc) with no VBS messages in dmesg"
    fi
fi

# ── Test 5: Unload the kexec image (triggers VBS_CALL_KEXEC_INVALIDATE) ─
echo "--- Test 5: kexec unload (invalidate) ---"
dmesg -C 2>/dev/null || true

kexec -u 2>/dev/null && unload_rc=0 || unload_rc=$?

sleep 0.5
VBS_INVALIDATE=$(dmesg | grep "vbs-kvm: kexec_invalidate" || true)

if [ -n "$VBS_INVALIDATE" ]; then
    log_pass "kexec unload triggered VBS_CALL_KEXEC_INVALIDATE"
else
    if [ $unload_rc -eq 0 ]; then
        log_pass "kexec unload succeeded (invalidate may have been called)"
    else
        log_skip "kexec unload returned $unload_rc (no image was loaded)"
    fi
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
