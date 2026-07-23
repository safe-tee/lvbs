# Bringing Up a Confidential VM with Coconut-SVSM in Plane 1 (AMD SEV-SNP + VM Planes)

## Overview

VM Planes is a KVM feature that creates multiple isolated execution contexts within a single VM. Each plane has its own vCPU array, register state, APIC, and memory attributes, while sharing the guest physical address space and I/O devices. On AMD SEV-SNP, **planes map directly to VMPLs** (VM Privilege Levels): the host KVM maintains `kvm->planes[vmpl]` so that Plane 0 = VMPL 2 (normal guest kernel) and Plane 1 = VMPL 0 (Coconut-SVSM, the privileged paravisor).

The hardware RMP (Reverse Map Table) enforces per-VMPL memory isolation, and VMSAs (VM Save Areas) provide per-VMPL register state — so each plane gets its own hardware-backed security domain.

---

## Phase 1: Host Preparation & VM Creation

**QEMU (userspace VMM) on the host:**

1. **`KVM_CREATE_VM`** — creates the VM, allocates `kvm->planes[0]` (Plane 0).

2. **`KVM_MEMORY_ENCRYPT_OP(KVM_SEV_SNP_LAUNCH_START)`** — initializes the SNP context:
   - Creates an SNP firmware context with guest policy (SMT, debug, API version, `SNP_POLICY_MASK_RSVD_MBO`).
   - Binds an ASID to the SNP context.
   - Sets `kvm->arch.has_protected_state = true`.

3. **Create Plane-0 vCPUs** — `KVM_CREATE_VCPU` for each BSP/AP at VMPL 2.
   Each vCPU gets a VMSA page allocated via `snp_safe_alloc_page()` (stored in `svm->sev_es.vmsa`).

4. **`KVM_SEV_SNP_LAUNCH_UPDATE`** (multiple times) — populates guest memory:
   - Loads OVMF firmware, kernel, initrd into guest memfd (`KVM_GUEST_MEMFD`).
   - For each page: `kvm_gmem_populate()` → `sev_gmem_post_populate()` → firmware `SEV_CMD_SNP_LAUNCH_UPDATE`.
   - Updates the RMP: `rmp_make_private(pfn, gfn, PG_LEVEL_4K, asid, immutable=true)`.
   - Page types: `NORMAL`, `ZERO`, `UNMEASURED`, `SECRETS` (contains SVSM base/size/CAA), `CPUID`.

5. **Inject SVSM Secrets Page** — a special `SNP_PAGE_TYPE_SECRETS` page is loaded at a well-known GPA containing:
   ```c
   struct snp_secrets_page {
       u64 svsm_base;        // physical address of Coconut-SVSM image
       u64 svsm_size;        // size of SVSM memory region
       u64 svsm_caa;         // SVSM Calling Area physical address
       u32 svsm_max_version; // max protocol version
       u8  svsm_guest_vmpl;  // VMPL where guest runs (2)
   };
   ```

6. **Load Coconut-SVSM image** into guest memory at `svsm_base` via `SNP_LAUNCH_UPDATE` with appropriate page type. This is the SVSM binary that will execute at VMPL 0.

---

## Phase 2: VMSA Creation & SNP Launch Finalization

7. **`KVM_SEV_SNP_LAUNCH_FINISH`** — finalizes the launch:
   - **`snp_launch_update_vmsa()`** — for each vCPU:
     - `sev_es_sync_vmsa()` syncs the VMCB save area into the VMSA page (GPRs, CRs, segments, XCR0, SEV features).
     - Marks VMSA as firmware-owned: `rmp_make_private(pfn, INITIAL_VMSA_GPA=0xFFFFFFFFF000, ...)`.
     - Issues `SEV_CMD_SNP_LAUNCH_UPDATE` with `page_type=SNP_PAGE_TYPE_VMSA`.
     - Sets `guest_state_protected = true`.
   - Issues `SEV_CMD_SNP_LAUNCH_FINISH` to the PSP firmware — from this point, the guest memory and VMSAs are cryptographically sealed and measured.

---

## Phase 3: Coconut-SVSM Boot (VMPL 0 / Plane 1)

8. **QEMU issues `KVM_RUN`** on the BSP vCPU. The hardware enters the guest at the firmware entry point.

9. **Coconut-SVSM initializes first** (VMPL 0):
   - The SNP firmware hands control to VMPL 0 first (highest privilege).
   - Coconut-SVSM's entry point runs in 64-bit long mode with its own VMSA.
   - It initializes the SVSM Calling Area (CAA) at the address from the secrets page.
   - Sets up its internal state: RMP management, PVALIDATE capability, vTPM, attestation services.
   - Registers SVSM protocol handlers:
     - **Protocol 0 (Core)**: `PVALIDATE`, `CREATE_VCPU`, `DELETE_VCPU`
     - **Protocol 1**: Attestation
     - **Protocol 2**: vTPM
     - **Protocol 3**: VBS extensions (for plane-based security services)

10. **SVSM issues `SVM_VMGEXIT_SNP_RUN_VMPL`** to transfer execution down to VMPL 2 (the guest kernel's plane).

---

## Phase 4: Guest Kernel Boot (VMPL 2 / Plane 0)

11. **OVMF firmware** starts at VMPL 2 — loads the UKI (Unified Kernel Image) containing:
    - `systemd-stub` (EFI stub)
    - `bzImage` (Plane-0 Linux kernel, built with `CONFIG_VM_PLANES=y`)
    - initramfs (containing `/config-vm-planes` and `/boot/plane-1/vmlinux`)

12. **Plane-0 Linux kernel** boots, detects it's an SEV-SNP guest at VMPL 2:
    - `cc_platform_has(CC_ATTR_GUEST_SEV_SNP)` → true
    - `snp_vmpl > 0` → SVSM is present
    - VBS probe table selects the **SEV-SNP backend** (`vbs_sev_snp_detect()` returns true)

13. **Plane-0 kernel parses** `enable-vm-planes=1` from cmdline → calls `arch_init_vm_planes()`.

---

## Phase 5: Plane 1 Setup via Hypercalls

14. **Hypercall 13 — `KVM_HC_VM_PLANES_CONFIG`**:
    - Plane-0 kernel reads `/config-vm-planes` from initramfs:
      ```
      PLANE_COUNT=2
      PLANE_1_KERNEL=/boot/plane-1/vmlinux
      PLANE_1_KERNEL_FORMAT=elf
      PLANE_1_LOAD_OFFSET=0x100000000
      PLANE_1_MEMORY_SIZE=0x60000000
      PLANE_1_VCPU_COUNT=1
      PLANE_1_CMDLINE="console=ttyS0 ..."
      ```
    - Issues `kvm_hypercall2(KVM_HC_VM_PLANES_CONFIG, phys_addr, plane_count)`.
    - KVM exits to QEMU (`KVM_EXIT_HYPERCALL`, nr=13).

15. **QEMU handles HC 13**:
    - Reads config from guest memory via `address_space_read()`.
    - **`KVM_CREATE_PLANE(1)`** → creates `kvm->planes[1]` with `struct kvm_svm_plane` containing `kvm_sev_info_plane` (per-plane VMSA features).
    - Allocates plane-1 RAM: `memory_region_init_ram("vm-plane-ram-1", 0x60000000)` at GPA `0x100000000`.
    - Creates plane-1 vCPU: `KVM_CREATE_VCPU` on the plane-1 fd.
    - Returns to guest.

16. **Plane-0 kernel loads Plane-1 kernel** from initramfs:
    - Reads `/boot/plane-1/vmlinux` (ELF format).
    - Validates ELF header (ELFCLASS64, EM_X86_64, ET_EXEC).
    - Iterates `PT_LOAD` segments, copies them to `load_offset + phdr->p_paddr`.
    - Computes entry point from `e_entry`.

17. **Hypercall 14 — `KVM_HC_VM_PLANES_ACTIVATE`**:
    - Issues `kvm_hypercall2(KVM_HC_VM_PLANES_ACTIVATE, phys_addr, plane_count)`.
    - KVM exits to QEMU (`KVM_EXIT_HYPERCALL`, nr=14).

18. **QEMU handles HC 14** — prepares plane-1 boot environment:

    **Writes boot infrastructure into plane-1 RAM (top = `0x160000000`):**

    | GPA | Content |
    |-----|---------|
    | `top - 0x10000` | Page tables: PML4 → PDPT → PD (identity-mapped, 2MB pages) |
    | `top - 0x4000` | GDT: NULL + 64-bit code (0x08) + 64-bit data (0x10) |
    | `top - 0x2000` | `boot_params` (Linux zero-page): header, e820 map, cmdline pointer |
    | `top - 0x1000` | Kernel command line string |

    **Sets plane-1 vCPU registers:**
    ```
    CR0 = PE | ET | NE | WP | PG        (0x80000035)
    CR3 = top - 0x10000                  (PML4 physical address)
    CR4 = PAE                            (0x20)
    EFER = SCE | LME | LMA | NXE        (0xF01)
    CS = {base=0, sel=0x08, limit=0xFFFFFFFF, L=1}  (64-bit code)
    DS/SS/ES/FS/GS = {base=0, sel=0x10}             (64-bit data)
    RSI = top - 0x2000                   (→ boot_params)
    RSP = top                            (stack)
    RIP = ELF entry point
    RFLAGS = 0x2
    ```

    **Starts plane-1 vCPU thread** → `KVM_RUN` in a new pthread.

---

## Phase 6: Plane-1 Kernel Execution

19. **Plane-1 Linux kernel** starts at `startup_64` in 64-bit long mode:
    - Initializes from `boot_params` (RSI).
    - Sets up early console (serial at 0x3f8 via `KVM_EXIT_IO`).
    - Unpacks built-in initramfs.
    - Runs `/init` → signals "Plane-1 secure kernel ready".
    - Halts (`HLT` → `KVM_EXIT_HLT`, QEMU pauses plane-1 thread).

20. **QEMU returns from HC 14** → Plane-0 resumes normal boot (systemd, rootfs mount, userspace).

---

## Phase 7: Runtime — Cross-Plane VBS Security Services

Both planes are now active. The VBS (Virtualization-Based Security) framework provides the communication protocol:

21. **Plane-0 → Plane-1 calls** use the **VBS KVM Planes backend** (`KVM_HC_VBS_VTL_CALL`, hypercall 15):
    ```c
    struct vbs_kvm_ca *ca = kvm_ca_page;   // shared memory calling area
    ca->call_id = VBS_CALL_SEAL_KERNEL;     // or PROTECT_MEMORY, VALIDATE_MODULE, etc.
    ca->arg_size = sizeof(req);
    memcpy(ca->buffer, &req, sizeof(req));
    ca->call_pending = 1;
    kvm_hypercall1(KVM_HC_VBS_VTL_CALL, virt_to_phys(ca));
    ```

22. **QEMU routes** the call to plane-1: wakes the plane-1 vCPU thread, which reads `ca->call_id`, processes the request, writes the response, and halts again.

23. **Simultaneously**, Coconut-SVSM at VMPL 0 handles **hardware-level** security services via the SVSM protocol (VMGEXIT-based):
    - `PVALIDATE` — page validation for memory acceptance
    - Attestation reports via `SNP_GUEST_REQUEST`
    - vTPM operations
    - **VBS Protocol 3** extensions — bridging the software VBS layer with hardware SVSM
