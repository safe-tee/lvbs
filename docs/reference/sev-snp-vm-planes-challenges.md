# SEV-SNP + VM Planes: Integration Challenges & Future Work

## Current Limitation: `has_protected_state`

```c
// arch/x86/kvm/x86.c:14536
int kvm_arch_nr_vcpu_planes(struct kvm *kvm)
{
    /* TODO: use kvm_x86_ops so that SNP can use planes for VTPLs. */
    return kvm->arch.has_protected_state ? 1 : KVM_MAX_VCPU_PLANES;
}
```

SEV-SNP VMs set `has_protected_state = true`, which currently forces single-plane mode. The TODO comment indicates this is a known limitation with a planned fix path.

---

## Challenge 1: Per-VM vs Per-Plane Protected State

**Problem**: `has_protected_state` is a global per-VM flag. When set, KVM restricts access to CR8, MSRs, debug registers, etc. for ALL vCPUs.

- Plane-0 guest (VMPL 2) should run with restrictions ✓
- Plane-1 SVSM (VMPL 0) needs unrestricted access to manage RMP, VMPL state ✗

**Solution**: Make `has_protected_state` a per-plane flag, not per-VM.

---

## Challenge 2: VMPL0 Creation Guard

```c
// Only VMPL0 can create/modify VMPL0 vCPUs
if (vmpl == SVM_SEV_VMPL0 &&
    (vcpu == target_vcpu || vcpu->plane_level != SVM_SEV_VMPL0))
    return -EINVAL;
```

**Problem**: Prevents non-VMPL0 code from creating VMPL0 vCPUs. If Coconut-SVSM runs in Plane 1 as VMPL 0, the initial plane creation from QEMU (which acts on behalf of Plane 0 / VMPL 2) is blocked.

**Solution**: Track per-plane VMPL mappings so the creation path understands that Plane 1 → VMPL 0 is the intended mapping.

---

## Challenge 3: VBS Backend Exclusivity

```c
// Only ONE backend wins (first match exits loop)
for (i = 0; i < ARRAY_SIZE(vbs_probe_table); i++) {
    if (e->detect())
        return vbs_register_backend(e->get_ops());
}
```

**Problem**: Can't use SEV-SNP backend (for direct SVSM communication) AND KVM Planes backend (for software plane orchestration) simultaneously.

**Solution**: Introduce per-plane VBS backend selection, or a composite backend that routes hardware operations to SEV-SNP and software operations to KVM Planes.

---

## Challenge 4: VMPL Detection Ambiguity

```c
bool vbs_sev_snp_detect(void) {
    if (!cc_platform_has(CC_ATTR_GUEST_SEV_SNP))
        return false;
    if (snp_vmpl == 0)
        return false;   // ← We ARE the SVSM
    return true;
}
```

**Problem**: Detection assumes "VMPL 0 = SVSM, VMPL > 0 = guest". For Plane 1 running Coconut-SVSM, `snp_vmpl == 0` inside Plane 1, but Plane 0's kernel sees `snp_vmpl > 0`.

**Solution**: Coordinate VMPL assignment per-plane so each plane knows its role.

---

## Challenge 5: ASID Management Across Planes

```c
// Single ASID per VM today
rmp_make_private(pfn, gfn << PAGE_SHIFT, PG_LEVEL_4K,
                 sev->asid,   // ← one ASID for all
                 true);
```

**Problem**: Single ASID per VM, but multi-VMPL mode needs per-VMPL ASID tracking for the RMP to enforce isolation between planes.

**Solution**: Allocate N ASIDs (one per active VMPL), tracked per-plane in `kvm_sev_info_plane`.

---

## Challenge 6: Shared Page Transitions

```c
kvm_rmp_make_shared(kvm, pfn, PG_LEVEL_4K);
rmp_make_private(pfn, gfn, PG_LEVEL_4K, asid, false);
```

**Problem**: Current logic assumes single-owner page transitions. Plane 0 ↔ Plane 1 IPC requires coordinated shared memory regions where both planes can access specific pages.

**Solution**: Shared memory protocol with RMP state management per-plane, similar to the existing `svsm_ca` (Calling Area) pattern.

---

## Summary: Required Changes

| Component | Current State | Required for Coconut-SVSM in Plane 1 |
|-----------|---------------|---------------------------------------|
| `has_protected_state` | Global per-VM | Per-plane flag |
| VMPL0 creation guard | Prevents VMPL0 by non-VMPL0 | Allow per-plane VMPL coordination |
| VBS backend | Single active | Per-plane backend (or composite) |
| VMPL detection | Assumes VMPL0=SVSM, VMPL>0=guest | Per-plane awareness |
| ASID management | Single per-VM | Per-VMPL (allocate N ASIDs) |
| Page sharing | Single-owner model | Coordinated P0↔P1 transitions |
| NumVMPL CPUID | Hidden (cleared) | Expose for multi-VMPL coordination |

---

## Dual Security Layer Benefit

With these changes, Coconut-SVSM in Plane 1 provides two complementary isolation mechanisms:

| Layer | Mechanism | Enforced By | Provides |
|-------|-----------|-------------|----------|
| **Hardware** | VMPL 0 (SVSM) vs VMPL 2 (guest) | AMD RMP table, PSP firmware | Cryptographic memory isolation, attestation, PVALIDATE |
| **Software** | Plane 1 (secure kernel) vs Plane 0 (guest kernel) | KVM plane isolation, separate vCPU arrays | Orchestration, HEKI, module validation, kexec control |

The hardware layer provides cryptographic guarantees. The software layer gives Coconut-SVSM a full Linux environment in Plane 1 to implement rich security policies that go beyond what bare-metal SVSM firmware alone can offer.
