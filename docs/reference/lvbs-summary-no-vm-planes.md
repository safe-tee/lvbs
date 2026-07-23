# LVBS: VTL0/VTL1 Kernel Bring-Up and Communication Summary

Based on the [128 patches](https://github.com/snambakam/lvbs/blob/qemu/docs/lvbs-patches.md) in CBL-Mariner-Linux-Kernel.

---

## VTL0 Kernel Bring-Up

1. **EFI Stub / VSM Awareness** — The EFI stub (`x86-stub.c`) checks Hyper-V OS loader indications to determine if VSM is supported before enabling it (#20)
2. **VSM Boot Driver** (`hv_vsm_boot`) — After VTL0 initcalls complete (#28), the boot driver:
   - Reserves memory for the secure kernel (#19, #40, #44)
   - Verifies signatures of the secure loader and secure kernel (#29)
   - Loads the secure kernel (supports ELF format) (#30, #31)
   - Enables VTL1 and boots the primary CPU in VTL1 (#21)
   - Boots secondary processors in VTL1 (#24, #27)
   - Passes ACPI data to the secure kernel (#46)
3. **HEKI Initialization** — After VTL1 is running:
   - Registers the Hyper-V heki_hypervisor (#2)
   - Walks kernel page tables to gather permissions (#3, #4)
   - Passes page permissions to VTL1 to set EPT protections (#6)
   - Signals "end of boot" to make VTL0 kernel immutable (#7, #54)
4. **Post-Boot VTL0** — Sends kernel data (#63), symbol tables (#68), system certificates (#13), and blacklist/revocation keyrings (#78) to VTL1

## VTL1 Secure Kernel Bring-Up

1. **VTL1 Driver** (`mshv_vsm_vtl1`) — Runs in VTL1 (#22):
   - Handles VTL parameters (#23)
   - Enables VTL1 for secondary CPUs (#25, #26)
   - Uses ACPI tables to map cpuid→apicid (#47)
   - Skips VMBUS channel creation in VTL1 (#62)
2. **Register Locking** — Locks critical control registers (CR0, CR4, etc.) via secure intercepts (#51, #52)
3. **Memory Protection** — Controls EPT permissions for VTL0 memory (#55, #56, #57)
4. **End-of-Boot Signal** — Handles VTL0's end-of-boot notification (#54), after which changes to EPT require authentication

## Communication Mechanisms (VTL0 ↔ VTL1)

| Mechanism | Direction | Purpose |
|-----------|-----------|---------|
| **VTL Call** (`__hv_vsm_init_vtlcall`) | VTL0 → VTL1 | Primary hypercall-based RPC mechanism. VTL0 issues a Hyper-V hypercall that switches execution to VTL1. Reworked in #33 and simplified in #32. |
| **Secure Intercepts** | VTL0 → VTL1 (implicit) | VTL1 registers intercepts (#52) so that certain VTL0 operations (e.g., writing to CR registers) trap into VTL1 for validation. Uses a common interrupt handler (#53). |
| **Shared Memory / Register Access** | VTL1 → VTL0 | VTL1 can read/write VTL0 registers (#50) and map VTL0 memory into its address space (#64). |
| **EPT Permission Control** | VTL1 → Hypervisor | VTL1 calls the hypervisor to set/modify EPT permissions for VTL0 pages (#55, #56). This enforces memory protections from above. |
| **Module Authentication** | VTL0 → VTL1 → VTL0 | VTL0 sends module contents to VTL1 (#67, #71), VTL1 validates signatures (#66, #70), applies relocations (#72, #73), sets EPT permissions for module sections (#74), and signals success. VTL0 can also request module unload (#75). |
| **Key/Certificate Exchange** | VTL0 → VTL1 | VTL0 sends system certificates (#13), runtime secondary keys (#76), and blacklist/revocation keyrings (#78) to VTL1. VTL1 receives and installs them (#77, #79). |
| **Kexec Validation** | VTL0 → VTL1 | VTL0 sends the kernel blob (#85) and kexec data (#87) to VTL1 for signature verification (#86) before allowing kexec. VTL1 protects kexec segments (#94) and validates/invalidates kexec requests (#84, #90). |
| **HEKI Page Protection** | VTL0 → VTL1 | VTL0 walks its page tables and sends page permissions to VTL1 (#6), which sets EPT accordingly. After boot, VTL0 uses VTL calls for authenticated operations like jump label patching (#15). |

---

The core pattern: **VTL0 requests, VTL1 validates/enforces.** All security-sensitive operations (module loading, kexec, memory permission changes, register modifications) must go through VTL1 for approval after the initial boot phase.
