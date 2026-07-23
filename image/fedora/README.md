# VM Plane orchestration

## Introduction

The VM boot sequence will include secure-boot through a UKI (Unified Kernel Image).

The UKI will contain the following artifacts:

1. UEFI boot stub (systemd-boot)
2. Kernel Image for Plane 0
3. Kernel Image for Plane 1
4. Intramfs
    1. Kernel command line for Plane 0
    2. Kernel command line for Plane 1
    3. Boot loader for Kernel in Plane 1
    4. Plane configuration (planes.json)

## Secure Boot sequence

1. Firmware (UEFI) verifies boot stub
2. Boot stub verifies UKI
3. Boot stub load Kernel 1 into Plane 0

    Minimal bring-up

    1. CPU, memory, ACPI, SMP setup
    2. No modules, no userspace, no dynamic code execution

    Hypervisor interaction

    1. Enable VTLs/VM Planes via. hypercalls
    2. Reserve memory regions for VTL1

    VTL1 secure staging
    
    1. Extract the VTL1 kernel from initrd
    2. Verify authenticity (signature hash, policy)

    Transfer of control

    1. Enter the VTL1 execution context
    2. Hand off CPU(s) to the VTL1 secure kernel

    Once booted, VTL1:

    1. Completes its own kernel initialization
    2. Applies immutable protections, including:
        * Kernel text and rodata protections
        * Page permission enforcement
        * Control register locking
    3. Establishes policy for authenticated operations
        * Module loading
        * Test patching / livepatch
        * kexec

    After protections are in place, VTL1 signals the end of its boot and only authenticated transitions from VTL0 are permitted thereafter.

    Return to VTL0

    1. VTL0 resumes normal boot
    2. init and userspace are started
    3. All sensitive operations are mediated by VTL1 through defined interfaces

Notes:

1. All components within initramfs of UKI are validated.
2. Kernel 2 (in Plane 1) is launched before userspace is launched.

## Build Folder Manifest

1. image -- where the VM image is composed
2. vmm/cloud-hypervisor -- orchestration through cloud-hypervisor
3. vmm/qemu -- orchestration through qemu

