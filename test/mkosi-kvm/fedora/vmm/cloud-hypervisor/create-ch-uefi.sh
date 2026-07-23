#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_DIR="$SCRIPT_DIR/../../../../../image/fedora"

cloud-hypervisor \
    --kernel /path/to/CLOUDHV_EFI.bin \
    --disk path="$IMAGE_DIR/fedora-kvm.raw" \
    --cpus boot=2 \
    --memory size=1G \
    --net tap=,mac=,ip=,mask=
