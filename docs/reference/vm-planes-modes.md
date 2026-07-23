# VBS Ops — How VM Planes Work Across Platforms

## Overview

`vbs_ops` is a backend abstraction layer defined in `include/linux/vbs.h` that provides a
single, transport-agnostic API for Virtualization-Based Security (VBS). The guest kernel calls
generic `vbs_*()` functions (e.g., `vbs_seal_kernel()`, `vbs_protect_memory()`), and those
dispatch through a single registered backend's `vbs_ops` function table.

## Architecture

```
Guest kernel subsystems
  (module loader, HEKI, kexec, key management)
           │
           ▼
    ┌─────────────┐
    │  vbs core    │  security/vbs/core.c
    │  (dispatch)  │  Single global: static const struct vbs_ops *vbs_backend
    └──────┬──────┘
           │  calls ops->protect_memory(), ops->seal_kernel(), etc.
           ▼
  ┌────────────────────────────────────────────────────────┐
  │              vbs_ops backend (one active)               │
  ├──────────────┬──────────────┬───────────┬──────────────┤
  │ KVM Planes   │ AMD SEV-SNP  │ Intel TDX │ Arm CCA      │ Hyper-V VSM
  │ kvm_planes.c │ sev_snp.c    │ tdx.c     │ arm_cca.c    │ hv_vsm.c
  └──────┬───────┴──────┬───────┴─────┬─────┴──────┬───────┴──────┬──────┘
         │              │             │            │              │
    kvm_hypercall   VMGEXIT/      TDVMCALL     SMC RSI       hv_do_
    (paravirt)      SVSM CAA      (R11=VBS)    HOST_CALL     hypercall
         │              │             │            │              │
         ▼              ▼             ▼            ▼              ▼
    QEMU/KVM        SVSM@VMPL0   Service TD    RMM/Host      Hyper-V
    plane-1 vCPU    (secure fw)   (separate TD) (realm svc)   VTL1 SK
```

## Backend Selection

At `device_initcall` time, `security/vbs/probe.c` walks the probe table in priority order —
first match wins:

| Priority | Backend | Detection | Transport |
|---|---|---|---|
| 1 | **AMD SEV-SNP** | `cc_platform_has(CC_ATTR_GUEST_SEV_SNP)` && `snp_vmpl != 0` | VMGEXIT → SVSM protocol 3 (VBS) at VMPL0 |
| 2 | **Intel TDX** | `cc_platform_has(CC_ATTR_GUEST_TDX)` | TDVMCALL leaf `0x10010000` → Service TD via VMM |
| 3 | **Arm CCA** | `is_realm_world()` | `SMC_RSI_HOST_CALL` → RMM/host security service |
| 4 | **Hyper-V VSM** | `hv_is_hyperv_initialized()` && `ms_hyperv.vtl == 0` | `HVCALL_VBS_REQUEST` → VTL1 secure kernel |
| 5 | **KVM Planes** | `kvm_para_available()` | `kvm_hypercall1(KVM_HC_VBS_VTL_CALL, phys)` → QEMU → plane-1 |

Hardware CoCo backends are mutually exclusive (a CPU is SEV-SNP *or* TDX *or* CCA). KVM Planes
is lowest priority because it is the software-emulation fallback.

## The `vbs_ops` Interface

Every backend implements the same set of callbacks:

| Callback | Purpose |
|---|---|
| `init` / `shutdown` | Lifecycle — allocate shared memory, connect to secure kernel |
| `vtl_call` | Raw request/response RPC to the secure kernel |
| `protect_memory` | Set R/W/X permissions on physical page ranges (HEKI) |
| `seal_kernel` | Make kernel text + rodata immutable from lower plane |
| `validate_module` | Send module ELF to secure kernel for signature verification |
| `set_module_perms` | Set per-section EPT/NPT permissions (text=RX, rodata=R, data=RW) |
| `unload_module` | Notify secure kernel to release EPT overrides |
| `add_key` / `revoke_key` / `send_certs` | Key and certificate management |
| `kexec_validate` / `kexec_invalidate` | Validate kexec kernel before allowing jump |

## Per-Platform Details

### KVM Planes (software emulation)

**Source:** `security/vbs/kvm_planes.c`

- **plane-0** = normal guest kernel, **plane-1** = secure kernel in a separate KVM plane
  managed by QEMU.
- **Communication:** Allocates a shared 4K calling-area page (`struct vbs_kvm_ca`), issues
  `KVM_HC_VBS_VTL_CALL` hypercall. KVM exits to QEMU (`KVM_EXIT_HYPERCALL`), QEMU routes the
  request to the plane-1 vCPU which processes it and writes back the response.
- **Isolation:** The KVM plane infrastructure (`struct kvm_plane` in `include/linux/kvm_host.h`)
  provides per-plane vCPU arrays, memory attribute arrays, and APIC state. Each plane has its
  own EPT/NPT so plane-1 can enforce memory protections on plane-0.

### AMD SEV-SNP

**Source:** `security/vbs/sev_snp.c`

- "Planes" map to **VMPLs** (Virtual Machine Privilege Levels). The guest kernel runs at
  VMPL2+, the **SVSM** (Secure VM Service Module) runs at VMPL0.
- **Communication:** `svsm_perform_call_protocol()` → `VMGEXIT` with
  `SVM_VMGEXIT_SNP_RUN_VMPL`. Arguments are passed via the SVSM Calling Area (CAA). VBS is
  assigned SVSM protocol number 3 (`SEV_SNP_VBS_CALL(x) = (3ULL << 32) | x`).
- **Isolation:** Hardware-enforced via the RMP (Reverse Map Table), which gates per-VMPL page
  access. The SVSM at VMPL0 controls VMPL permission bitmaps.
- **Note:** KVM VM Planes are not yet usable for SNP — `kvm_arch_nr_vcpu_planes()` returns 1
  for protected VMs. See `vm-planes-todo-issues.md` Issue #1.

### Intel TDX

**Source:** `security/vbs/tdx.c`

- "Plane-1" maps to a **Service TD** — a separate Trust Domain that provides security services
  to the main TD.
- **Communication:** `__tdx_hypercall()` with `R11 = TDVMCALL_VBS (0x10010000)`,
  `R12` = VBS command, `R13`/`R14` = physical addresses of shared (decrypted) request/response
  pages, `R15` = request size. The VMM routes the call to the service TD.
- **Shared memory:** Pages are converted via `set_memory_decrypted()` (clears the GPA
  encryption bit) so the service TD can read them.
- **Isolation:** Native TDX module isolation — does not use KVM VM Planes on the host side.
  The Service TD architecture is still evolving.

### Arm CCA

**Source:** `security/vbs/arm_cca.c`

- The Realm guest is the "plane-0". The security service runs in the host or RMM (Realm
  Management Monitor).
- **Communication:** `arm_smccc_smc(SMC_RSI_HOST_CALL, ipa_of_request_page, ...)`. The request
  is structured with a `CCA_VBS_MAGIC` header in a shared page (converted to `RIPAS_EMPTY` via
  `set_memory_decrypted()`).
- **Isolation:** Enforced by the Granule Protection Table (GPT) and RIPAS state machine in the
  RMM. Protected pages (`RIPAS_RAM`) are inaccessible to the host; shared pages (`RIPAS_EMPTY`)
  are used for communication.
- Does not use KVM VM Planes — the RMM provides the hardware-enforced boundary.

### Hyper-V VSM

**Source:** `security/vbs/hv_vsm.c`

- "Planes" are **VTLs** (Virtual Trust Levels). VTL0 = normal OS, VTL1 = secure kernel
  (SKCI / Credential Guard).
- **Communication:** `hv_do_hypercall(HVCALL_VBS_REQUEST, input_page, output_page)`. The
  hypervisor routes to the VTL1 secure kernel.
- **Isolation:** Per-VTL SLAT (EPT/NPT) tables controlled by Hyper-V. VTL1 can restrict
  VTL0's access to any page.
- This is the model that KVM VM Planes is designed to emulate in software.

## Summary Table

| | KVM Planes | AMD SEV-SNP | Intel TDX | Arm CCA | Hyper-V VSM |
|---|---|---|---|---|---|
| **"Plane-1" is** | KVM plane-1 vCPU (QEMU) | SVSM @ VMPL0 | Service TD | RMM / host service | VTL1 secure kernel |
| **Isolation by** | Per-plane EPT (software) | RMP + VMPLs (hardware) | TDX module / separate TD | GPT + RIPAS (hardware) | Per-VTL SLAT (hypervisor) |
| **Transport** | KVM paravirt hypercall | VMGEXIT + CAA | TDVMCALL + shared pages | SMC RSI_HOST_CALL | Hyper-V hypercall |
| **Shared memory** | Calling-area page (cleartext) | SVSM CAA buffer | Decrypted pages (`cc_mkdec`) | RIPAS_EMPTY pages | Hypercall I/O pages |
| **Uses KVM VM Planes?** | Yes (directly) | Not yet (blocked) | No (native TDX) | No (native CCA) | No (native VTL) |
