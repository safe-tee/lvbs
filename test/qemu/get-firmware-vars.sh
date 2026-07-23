#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VARS_FILE=OVMF_VARS_4M.qcow2
SRC="/usr/share/edk2/ovmf/$VARS_FILE"
# Per-VM writable NVRAM store lives next to the launch scripts (runtime
# artifact, not part of the mkosi image source under image/fedora).
DST="$SCRIPT_DIR/$VARS_FILE"

if [ ! -f "$SRC" ]; then
    echo "Error: $SRC not found" >&2
    exit 1
fi

# Copy only if local copy is missing or differs from the source
if [ ! -f "$DST" ] || ! cmp -s "$SRC" "$DST"; then
    cp -f "$SRC" "$DST"
    chmod u+w "$DST"
    echo "Updated $DST"
fi
