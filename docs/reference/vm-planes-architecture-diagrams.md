# VM Planes Architecture Diagram

```mermaid
graph TB
    subgraph "AMD SEV-SNP Hardware"
        RMP["RMP Table<br/>(per-page VMPL permissions)"]
        PSP["AMD PSP<br/>(firmware attestation)"]
    end

    subgraph "Host (Linux + KVM)"
        QEMU["QEMU<br/>VM creation, plane management"]
        KVM["KVM SVM<br/>planes[], VMSA mgmt, RMP ops"]
    end

    subgraph "Guest VM"
        subgraph "VMPL 0 / Plane 1 — Coconut-SVSM"
            SVSM["Coconut-SVSM<br/>PVALIDATE, vTPM, Attestation"]
            VBS_P1["VBS Protocol 3<br/>Security services"]
        end
        subgraph "VMPL 2 / Plane 0 — Guest Kernel"
            GK["Linux Kernel<br/>CONFIG_VM_PLANES=y"]
            VBS_P0["VBS SEV-SNP Backend<br/>VMGEXIT → SVSM"]
            VBS_KVM["VBS KVM Planes Backend<br/>HC 15 → Plane 1"]
        end
    end

    QEMU -->|"KVM_CREATE_PLANE<br/>KVM_SEV_SNP_LAUNCH_*"| KVM
    KVM -->|"VMSA per VMPL<br/>RMP enforcement"| RMP
    KVM -->|"SNP_LAUNCH_FINISH"| PSP

    GK -->|"VMGEXIT<br/>SNP_RUN_VMPL"| SVSM
    GK -->|"HC 15<br/>VBS_VTL_CALL"| VBS_P1
    VBS_P0 -->|"SVSM CAA protocol"| SVSM
    VBS_KVM -->|"Shared memory CA"| VBS_P1
```

## Boot Sequence Diagram

```mermaid
sequenceDiagram
    participant QEMU as QEMU (Host)
    participant KVM as KVM (Host Kernel)
    participant PSP as AMD PSP
    participant SVSM as Coconut-SVSM<br/>(VMPL 0 / Plane 1)
    participant OVMF as OVMF Firmware<br/>(VMPL 2)
    participant P0 as Plane-0 Kernel<br/>(VMPL 2)
    participant P1 as Plane-1 Kernel<br/>(Software Plane)

    Note over QEMU,PSP: Phase 1: Host Preparation
    QEMU->>KVM: KVM_CREATE_VM
    QEMU->>KVM: KVM_SEV_SNP_LAUNCH_START (policy, ASID)
    KVM->>PSP: SEV_CMD_SNP_LAUNCH_START
    QEMU->>KVM: KVM_CREATE_VCPU × N (Plane 0)
    loop For each memory region
        QEMU->>KVM: KVM_SEV_SNP_LAUNCH_UPDATE (pages + SECRETS)
        KVM->>PSP: SEV_CMD_SNP_LAUNCH_UPDATE
    end

    Note over QEMU,PSP: Phase 2: Launch Finalization
    QEMU->>KVM: KVM_SEV_SNP_LAUNCH_FINISH
    KVM->>KVM: snp_launch_update_vmsa() — encrypt VMSAs
    KVM->>PSP: SEV_CMD_SNP_LAUNCH_FINISH
    Note over KVM: Guest memory & VMSAs sealed

    Note over SVSM,P0: Phase 3: Coconut-SVSM Boot
    QEMU->>KVM: KVM_RUN (BSP)
    KVM-->>SVSM: Hardware enters VMPL 0 first
    SVSM->>SVSM: Init CAA, RMP mgmt, vTPM, attestation
    SVSM->>SVSM: Register protocols 0-3
    SVSM-->>OVMF: SVM_VMGEXIT_SNP_RUN_VMPL → VMPL 2

    Note over OVMF,P0: Phase 4: Guest Kernel Boot
    OVMF->>OVMF: Load UKI (bzImage + initramfs)
    OVMF-->>P0: Boot Linux kernel
    P0->>P0: Detect SEV-SNP (snp_vmpl > 0)
    P0->>P0: VBS probe → SEV-SNP backend
    P0->>P0: Parse enable-vm-planes=1

    Note over QEMU,P1: Phase 5: Plane 1 Setup
    P0->>KVM: HC 13 (VM_PLANES_CONFIG)
    KVM-->>QEMU: KVM_EXIT_HYPERCALL (nr=13)
    QEMU->>KVM: KVM_CREATE_PLANE(1)
    QEMU->>QEMU: Allocate plane-1 RAM (1.5 GB @ 0x100000000)
    QEMU->>KVM: KVM_CREATE_VCPU on plane-1
    QEMU-->>P0: Return from HC 13

    P0->>P0: Load plane-1 ELF kernel from initramfs
    P0->>P0: Copy PT_LOAD segments to load_offset

    P0->>KVM: HC 14 (VM_PLANES_ACTIVATE)
    KVM-->>QEMU: KVM_EXIT_HYPERCALL (nr=14)
    QEMU->>QEMU: Write page tables, GDT, boot_params
    QEMU->>KVM: KVM_SET_SREGS + KVM_SET_REGS (plane-1 vCPU)

    Note over P1: Phase 6: Plane-1 Execution
    QEMU->>KVM: KVM_RUN (plane-1 vCPU thread)
    KVM-->>P1: startup_64 (RIP = ELF entry, RSI = boot_params)
    P1->>P1: Init console, unpack initramfs
    P1->>P1: /init → "Plane-1 ready"
    P1-->>QEMU: HLT → KVM_EXIT_HLT
    QEMU-->>P0: Return from HC 14

    Note over P0,P1: Phase 7: Runtime VBS Calls
    P0->>KVM: HC 15 (VBS_VTL_CALL) — seal_kernel
    KVM-->>QEMU: KVM_EXIT_HYPERCALL (nr=15)
    QEMU->>P1: Wake plane-1 vCPU
    P1->>P1: Process VBS_CALL_SEAL_KERNEL
    P1-->>QEMU: HLT (done)
    QEMU-->>P0: Return from HC 15
```

## Dual Security Layers

```mermaid
graph LR
    subgraph "Hardware Layer (AMD SEV-SNP)"
        direction TB
        HW_VMPL0["VMPL 0<br/>Coconut-SVSM"]
        HW_VMPL2["VMPL 2<br/>Guest Kernel"]
        HW_RMP["RMP Table"]
        HW_VMPL0 ---|"cryptographic isolation"| HW_RMP
        HW_VMPL2 ---|"cryptographic isolation"| HW_RMP
    end

    subgraph "Software Layer (KVM VM Planes)"
        direction TB
        SW_P1["Plane 1<br/>Secure Kernel"]
        SW_P0["Plane 0<br/>Guest Kernel"]
        SW_VBS["VBS Framework"]
        SW_P0 ---|"HC 15 / shared CA"| SW_VBS
        SW_VBS ---|"orchestration"| SW_P1
    end

    HW_VMPL0 -.-|"maps to"| SW_P1
    HW_VMPL2 -.-|"maps to"| SW_P0
```

| Layer | Mechanism | Enforced By | Provides |
|-------|-----------|-------------|----------|
| **Hardware** | VMPL 0 (SVSM) vs VMPL 2 (guest) | AMD RMP table, PSP firmware | Cryptographic memory isolation, attestation |
| **Software** | Plane 1 (secure kernel) vs Plane 0 (guest kernel) | KVM plane isolation, separate vCPU arrays | Orchestration, kernel integrity (HEKI), module validation, kexec control |
