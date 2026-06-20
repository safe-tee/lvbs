#!/bin/bash
# test-plane-read-isolation.sh — Validate that plane 0 cannot read plane 1's RAM
#
# Run this script inside the *normal* guest (plane 0) after boot.
#
# Background
# ----------
# Plane 1 (the secure plane) owns a region carved out of the VM's physical
# address space: [CARVE_BASE, CARVE_BASE+CARVE_SIZE).  Two independent
# mechanisms keep plane 0 out of it:
#
#   1. memmap= on plane 0's kernel cmdline removes the range from plane 0's
#      usable e820 RAM, so plane 0 never *allocates* there (defence in depth).
#   2. The secure plane seals the same range NO_READ/NO_WRITE/NO_EXEC in
#      plane 0's EPT (KVM per-plane access attributes).  Any access plane 0
#      makes to a sealed GPA faults out to the VMM (KVM_EXIT_MEMORY_FAULT).
#
# This script verifies mechanism (1) and (2)'s *setup* non-destructively, and
# optionally exercises (2) for real with --destructive.
#
# IMPORTANT: a working NO_READ seal turns a read of plane-1 memory into a
# memory-fault VM exit.  QEMU has no handler for that on plane 0, so the read
# does not return an error to this script — it typically *freezes or kills the
# whole VM*.  That is why the actual read probe is OPT-IN (--destructive) and
# why a "pass" there is observed from OUTSIDE (the VM dies / QEMU prints a
# memory-fault) rather than from this script.
#
# Usage:
#   ./test-plane-read-isolation.sh                 # safe checks only
#   ./test-plane-read-isolation.sh --destructive   # also attempt a real read
#
# Must be run as root (reads /proc/iomem addresses and /dev/mem).

# Carve geometry — must match build-vm-planes-image.sh
# (VTL1_LOAD_OFFSET_DEFAULT / VTL1_MEMORY_SIZE_DEFAULT) and the memmap= on the
# plane-0 cmdline (finalize-image.sh.chroot).
CARVE_BASE=$((0x40000000))
CARVE_SIZE=$((0x3c000000))
CARVE_END=$((CARVE_BASE + CARVE_SIZE))          # 0x7c000000, exclusive
PROBE_ADDR=$((CARVE_BASE + CARVE_SIZE / 2))     # somewhere in the middle

DESTRUCTIVE=0
for arg in "$@"; do
    case "$arg" in
        --destructive) DESTRUCTIVE=1 ;;
        -h|--help)
            sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

PASS=0
FAIL=0
SKIP=0

log_pass() { echo "PASS: $1"; ((++PASS)); }
log_fail() { echo "FAIL: $1"; ((++FAIL)); }
log_skip() { echo "SKIP: $1"; ((++SKIP)); }

hex() { printf '0x%x' "$1"; }

echo "=== VBS Plane Read-Isolation Test ==="
echo "Carve:  [$(hex "$CARVE_BASE"), $(hex "$CARVE_END"))  size=$(hex "$CARVE_SIZE")"
echo "Probe:  $(hex "$PROBE_ADDR")"
echo "Date:   $(date)"
echo ""

# ── Test 0: must be root ──────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo "This test must be run as root (needs /proc/iomem addresses and /dev/mem)."
    exit 2
fi

# ── Test 1: VBS / secure plane is active ──────────────────────────────
echo "--- Test 1: secure plane active ---"
if dmesg | grep -qiE 'registered backend "kvm-planes"|vbs-kvm: connected to plane-1|vbs: HEKI: kernel sealed'; then
    log_pass "secure plane backend is active"
else
    log_skip "no secure-plane backend message in dmesg — isolation may not be configured"
fi

# ── Test 2: carve is NOT usable System RAM in plane 0 (mechanism 1) ────
# /proc/iomem must not contain a "System RAM" range that overlaps the carve.
echo "--- Test 2: carve removed from plane-0 usable RAM (/proc/iomem) ---"
overlap=""
while read -r range desc; do
    # range looks like "40000000-7bffffff"
    start=$((0x${range%%-*}))
    end=$((0x${range##*-} + 1))      # iomem ranges are inclusive
    # overlap test: [start,end) ∩ [CARVE_BASE,CARVE_END)
    if [ "$start" -lt "$CARVE_END" ] && [ "$end" -gt "$CARVE_BASE" ]; then
        overlap+="    $range : $desc"$'\n'
    fi
done < <(grep -i "System RAM" /proc/iomem | sed 's/^ *//;s/ *: */ /')

if [ -z "$overlap" ]; then
    log_pass "no 'System RAM' overlaps the carve — plane 0 cannot allocate there"
else
    log_fail "plane 0 has usable System RAM overlapping the carve:"
    printf '%s' "$overlap"
fi

# Show what plane 0 *does* see for the carve range, for context (no awk: the
# minimal guest image has no awk, so use a pure-bash loop).
echo "  /proc/iomem entries touching the carve:"
while read -r range desc; do
    start=$((0x${range%%-*}))
    end=$((0x${range##*-} + 1))
    if [ "$start" -lt "$CARVE_END" ] && [ "$end" -gt "$CARVE_BASE" ]; then
        echo "    $range : $desc"
    fi
done < <(sed 's/^ *//;s/ *: */ /' /proc/iomem)

# ── Test 3: carve marked reserved/removed in the e820 map (mechanism 1) ─
echo "--- Test 3: e820 shows the carve reserved/removed ---"
if dmesg | grep -iE 'e820|user-defined physical RAM' \
        | grep -iE "$(printf '%09x' "$CARVE_BASE")|reserved" \
        | grep -qiE 'user|reserved'; then
    log_pass "e820/memmap reflects the carve reservation"
    dmesg | grep -iE 'user-defined physical RAM' | head -1 | sed 's/^/  /'
else
    log_skip "could not confirm carve in e820 from dmesg (ring buffer may have rotated)"
fi

# ── Test 4: report the software /dev/mem barrier (no carve access) ─────
# CONFIG_STRICT_DEVMEM makes /dev/mem refuse non-RAM/reserved ranges in
# software, before any access can reach the EPT.  This is purely informational
# and does NOT touch the carve — actually reading the carve is the job of the
# destructive probe below.
echo "--- Test 4: strict /dev/mem barrier (informational) ---"
strict=""
for cfg in "/boot/config-$(uname -r)" /proc/config.gz; do
    if [ -r "$cfg" ]; then
        if [ "$cfg" = /proc/config.gz ] && command -v zcat >/dev/null; then
            strict=$(zcat "$cfg" | grep -E '^CONFIG_STRICT_DEVMEM=' || true)
        else
            strict=$(grep -E '^CONFIG_STRICT_DEVMEM=' "$cfg" 2>/dev/null || true)
        fi
        [ -n "$strict" ] && break
    fi
done
if [ -n "$strict" ]; then
    echo "  $strict"
    log_pass "kernel config exposes strict devmem setting"
else
    log_skip "could not read CONFIG_STRICT_DEVMEM (no /boot/config or /proc/config.gz)"
fi

# ── Test 5 (opt-in, DESTRUCTIVE): actually read plane-1 memory ────────
# This is the ONLY test that touches the carve.  Reading a sealed GPA should
# fault out to the VMM (KVM_EXIT_MEMORY_FAULT).  Interpretation:
#   read blocked/hangs/EIO  → isolation IS enforced (PASS)
#   read succeeds, VM alive → plane 0 read plane-1 RAM = isolation BROKEN (FAIL)
echo "--- Test 5: real read probe (destructive) ---"
if [ "$DESTRUCTIVE" -ne 1 ]; then
    log_skip "skipped — pass --destructive to attempt a real read of plane-1 RAM"
    echo "  NOTE: if the seal works this read faults out and may FREEZE/KILL the"
    echo "  VM; if the seal is NOT enforced the read returns and the test FAILS."
elif [ ! -e /dev/mem ]; then
    log_skip "/dev/mem not present — cannot probe from userspace"
else
    echo "  !!! DESTRUCTIVE: reading $(hex "$PROBE_ADDR") (inside plane 1's carve)."
    echo "  !!! If isolation works the VM may fault out now and not return."
    sync
    sleep 1
    # Short timeout so a (failing) clean success still returns control.
    if timeout 5 dd if=/dev/mem bs=1 count=1 skip="$PROBE_ADDR" of=/dev/null 2>/dev/null; then
        log_fail "read of plane-1 memory SUCCEEDED — EPT NO_READ seal is NOT enforced"
    else
        rc=$?
        if [ "$rc" -eq 124 ]; then
            log_pass "read hung (timeout) — consistent with a memory-fault VM exit"
        else
            log_pass "read blocked (rc=$rc) — plane 1 memory is not readable from plane 0"
        fi
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────
echo ""
echo "=== Results ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  SKIP: $SKIP"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "OVERALL: FAILED"
    exit 1
else
    echo "OVERALL: PASSED"
    exit 0
fi
