# VBS Backend Probe & Detection

## Backend Selection

The VBS (Virtualization-Based Security) framework probes backends in priority order — first match wins:

```c
// security/vbs/probe.c
static const struct vbs_probe_entry vbs_probe_table[] = {
    { "AMD SEV-SNP",    vbs_sev_snp_detect,      vbs_sev_snp_get_ops },     // Hardware
    { "Intel TDX",      vbs_tdx_detect,          vbs_tdx_get_ops },
    { "Arm CCA",        vbs_cca_detect,          vbs_cca_get_ops },
    { "Hyper-V VSM",    vbs_hv_vsm_detect,       vbs_hv_vsm_get_ops },      // Hypervisor
    { "KVM planes",     vbs_kvm_planes_detect,   vbs_kvm_planes_get_ops },  // Software
};
```

## SEV-SNP Backend (`security/vbs/sev_snp.c`)

Detects when running as an SEV-SNP guest at VMPL > 0 (i.e., SVSM is present at VMPL 0):

```c
bool vbs_sev_snp_detect(void) {
    if (!cc_platform_has(CC_ATTR_GUEST_SEV_SNP))
        return false;
    if (snp_vmpl == 0)      // We ARE the SVSM — don't use this backend
        return false;
    return true;             // Guest at VMPL > 0, SVSM is available
}
```

Transport: VMGEXIT → `SVM_VMGEXIT_SNP_RUN_VMPL` → SVSM CAA protocol.

VBS calls are encoded as SVSM Protocol 3:
```c
#define SEV_SNP_VBS_CALL(x)  ((3ULL << 32) | (x))
// RAX = call_id, RCX/RDX = arg physical addresses, R8/R9 = response buffers
```

## KVM Planes Backend (`security/vbs/kvm_planes.c`)

Detects when running in a KVM VM with planes enabled:

```c
bool vbs_kvm_planes_detect(void) {
    return kvm_para_has_feature(KVM_FEATURE_VM_PLANES);
}
```

Transport: Hypercall 15 (`KVM_HC_VBS_VTL_CALL`) → QEMU → Plane-1 vCPU.

```c
static int kvm_planes_vtl_call(enum vbs_call_id id,
                               const void *arg, size_t arg_size,
                               void *resp, size_t resp_size) {
    struct vbs_kvm_ca *ca = kvm_ca_page;

    ca->call_id = id;
    ca->arg_size = arg_size;
    if (arg_size && arg)
        memcpy(ca->buffer, arg, arg_size);
    ca->call_pending = 1;

    hc_ret = kvm_hypercall1(KVM_HC_VBS_VTL_CALL, virt_to_phys(ca));
    ca->call_pending = 0;

    if (resp && resp_size && ca->resp_size) {
        size_t copy = min(resp_size, ca->resp_size);
        memcpy(resp, ca->buffer, copy);
    }
    return ca->status;
}
```

## VBS Call Types

| Call ID | Purpose |
|---------|---------|
| `VBS_CALL_SEAL_KERNEL` | Lock kernel .text/.rodata as read-only |
| `VBS_CALL_PROTECT_MEMORY` | Set per-page permissions (R/W/X) |
| `VBS_CALL_VALIDATE_MODULE` | Verify kernel module ELF + signature |
| `VBS_CALL_SET_MODULE_PERMS` | Apply W^X to module pages |
| `VBS_CALL_UNLOAD_MODULE` | Revoke module page permissions |
| `VBS_CALL_ADD_KEY` | Register trusted signing key |
| `VBS_CALL_REVOKE_KEY` | Remove trusted signing key |

---

# Key Source Files

## Linux Kernel

| File | Purpose |
|------|---------|
| `init/vm_planes.c` | Config parsing, ELF loading for plane kernels |
| `include/linux/vm_planes.h` | Public VM Planes API |
| `virt/kvm/kvm_main.c` | KVM plane creation (lines ~1225, ~4358) |
| `include/linux/kvm_host.h` | `struct kvm_plane` definition (line ~872) |
| `arch/x86/kvm/x86.c` | Hypercall dispatch (line ~10570), `kvm_arch_nr_vcpu_planes()` (line ~14536) |
| `arch/x86/kvm/svm/sev.c` | SEV-SNP launch flow, AP creation, VMPL switching |
| `arch/x86/kvm/svm/svm.h` | `struct kvm_svm_plane`, `struct kvm_sev_info_plane` |
| `arch/x86/coco/sev/svsm.c` | Guest-side SVSM protocol implementation |
| `arch/x86/include/asm/sev.h` | SVSM structures, `snp_secrets_page`, VMPL definitions |
| `security/vbs/probe.c` | VBS backend detection & registration |
| `security/vbs/sev_snp.c` | VBS SEV-SNP backend (VMGEXIT transport) |
| `security/vbs/kvm_planes.c` | VBS KVM Planes backend (hypercall transport) |

## QEMU

| File | Purpose |
|------|---------|
| `accel/kvm/kvm-all.c` | `kvm_create_plane()` (~line 2855), `kvm_create_vcpu_plane()` (~line 576), HC dispatch |
| `include/system/kvm_int.h` | `struct KVMPlane`, `struct kvm_vm_plane_state` (lines ~106-125) |
