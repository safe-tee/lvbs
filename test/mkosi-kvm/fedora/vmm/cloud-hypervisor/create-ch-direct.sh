#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_DIR="$SCRIPT_DIR/../../../../../image/fedora"

cloud-hypervisor \
    --kernel "$IMAGE_DIR/fedora-kvm.vmlinuz" \
    --initramfs "$IMAGE_DIR/fedora-kvm.initrd" \
    --cmdline "root=/dev/vda2 console=ttyS0" \
    --disk path="$IMAGE_DIR/fedora-kvm.raw" \
    --cpus boot=2 \
    --memory size=1G

