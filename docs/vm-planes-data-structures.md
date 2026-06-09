# VM Planes Architecture: Data Structures & Interfaces

## Core Kernel Data Structures

### `struct kvm_plane` — Per-Plane Container

Each plane within a VM is represented by a `kvm_plane`:

```c
struct kvm_plane {
    struct kvm *kvm;                 // back-pointer to parent VM
    unsigned level;                  // plane index (0, 1, 2, ...)
    struct xarray vcpu_array;        // per-plane vCPU storage
    struct kvm_arch_plane arch;      // arch-specific data (e.g., SEV info)
};
```

In `struct kvm`:
```c
struct kvm_plane *planes[KVM_MAX_PLANES];  // up to 16 planes
bool has_planes;
```

### `struct kvm_svm_plane` — AMD SVM Per-Plane Extension

```c
struct kvm_sev_info_plane {
    u64 vmsa_features;               // shared SEV feature flags for this plane/VMPL
};

struct kvm_svm_plane {
    struct kvm_plane plane;           // generic plane container
    struct kvm_sev_info_plane sev_info_plane;
};
```

### QEMU-Side Structures

```c
struct KVMPlane {
    int kvm_fd;                       // plane vCPU file descriptor
    int kvm_vcpu_stats_fd;
    bool vcpu_dirty;
};

// In KVMState:
int plane_fds[KVM_MAX_PLANES];
struct kvm_vm_plane_state *vm_planes; // per-plane state from guest
```

---

## KVM Ioctls

| Ioctl | Number | Scope | Purpose |
|-------|--------|-------|---------|
| `KVM_CREATE_PLANE` | 0xe4 | VM | Create a new plane for a VMPL level |
| `KVM_CREATE_VCPU` | — | Plane | Create a vCPU on a specific plane fd |
| `KVM_MEMORY_ENCRYPT_OP` | 0xba | VM | Generic SEV command dispatcher |

### SEV-SNP Sub-commands (via `KVM_MEMORY_ENCRYPT_OP`)

| Command | Purpose |
|---------|---------|
| `KVM_SEV_SNP_LAUNCH_START` | Initialize SNP guest context |
| `KVM_SEV_SNP_LAUNCH_UPDATE` | Populate guest memory pages |
| `KVM_SEV_SNP_LAUNCH_FINISH` | Finalize launch & encrypt VMSAs |

### KVM Exit Types

| Exit | Number | Purpose |
|------|--------|---------|
| `KVM_EXIT_HYPERCALL` | — | Plane config/activate/VBS calls (HC 13, 14, 15) |
| `KVM_EXIT_PLANE_EVENT` | 44 | Triggered when guest AP creation needs a new plane/vCPU |

```c
struct kvm_plane_event_exit {
    #define KVM_PLANE_EVENT_CREATE_VCPU  1
    __u32 plane;        // target VMPL plane to create vCPU in
};
```

---

## Hypercall Interface

### Defined in `include/uapi/linux/kvm_para.h`

```c
#define KVM_HC_VM_PLANES_CONFIG     13   // guest → QEMU: allocate plane memory
#define KVM_HC_VM_PLANES_ACTIVATE   14   // guest → QEMU: activate plane vCPUs
#define KVM_HC_VBS_VTL_CALL         15   // guest → QEMU: inter-plane RPC (VBS)
```

### Hypercall Dispatch (KVM kernel, `arch/x86/kvm/x86.c`)

All three hypercalls exit to userspace (QEMU) for handling:

```c
case KVM_HC_VM_PLANES_CONFIG:
case KVM_HC_VM_PLANES_ACTIVATE:
case KVM_HC_VBS_VTL_CALL: {
    ret = -KVM_ENOSYS;
    if (!user_exit_on_hypercall(vcpu->kvm, nr))
        break;

    vcpu->run->exit_reason = KVM_EXIT_HYPERCALL;
    vcpu->run->hypercall.nr = nr;
    vcpu->run->hypercall.ret = 0;
    vcpu->run->hypercall.args[0] = a0;
    // ... fills args[1-5]
}
```

---

## VBS Calling Area (Cross-Plane Communication)

### Shared Memory Structure

```c
struct vbs_kvm_ca {
    __u8 call_pending;     // in-flight flag
    __u8 rsvd[3];
    __u32 call_id;         // enum vbs_call_id
    __s32 status;          // return code
    __u32 arg_size;
    __u32 resp_size;
    __u8 buffer[];         // request/response data (up to PAGE_SIZE - header)
};

#define VBS_CA_BUF_SIZE  (PAGE_SIZE - sizeof(struct vbs_kvm_ca))
```

### VBS Operations Interface

```c
struct vbs_ops {
    const char *name;
    int (*init)(void);
    void (*shutdown)(void);
    int (*vtl_call)(enum vbs_call_id id, const void *arg, size_t arg_size,
                    void *resp, size_t resp_size);
    int (*protect_memory)(unsigned long pfn, unsigned long nr_pages, unsigned int perms);
    int (*seal_kernel)(void);
    int (*validate_module)(const void *elf, size_t elf_size,
                           const void *sig, size_t sig_size);
    int (*set_module_perms)(const struct module *mod);
    int (*unload_module)(const struct module *mod);
    // ... key management, attestation, kexec
};
```

---

## SVSM Calling Area (Hardware-Level Communication)

### SVSM CAA Structure

```c
struct svsm_ca {
    u8 call_pending;                            // in-flight flag
    u8 mem_available;
    u8 rsvd1[6];
    u8 svsm_buffer[PAGE_SIZE - 8];              // 4088 bytes data
};
```

### SVSM Call Register Convention

```c
struct svsm_call {
    struct svsm_ca *caa;
    u64 rax;       // protocol (bits 63:32) | call_id (bits 31:0)
    u64 rcx, rdx, r8, r9;             // input registers
    u64 rax_out, rcx_out, rdx_out, r8_out, r9_out;  // output registers
};
```

### SVSM Protocol Numbers

| Protocol | Purpose |
|----------|---------|
| 0 | Core (PVALIDATE, CREATE_VCPU, DELETE_VCPU) |
| 1 | Attestation |
| 2 | vTPM |
| 3 | VBS Extensions (for service VMs / plane-based security) |

---

## VMPL ↔ Plane Mapping

On AMD SEV-SNP, each plane represents a VMPL level:

```
kvm->planes[0]  →  VMPL 2  (normal guest kernel)
kvm->planes[1]  →  VMPL 0  (Coconut-SVSM / paravisor)
kvm->planes[2]  →  VMPL 1  (optional, additional service)
kvm->planes[3]  →  VMPL 3  (optional, lowest privilege)
```

Each VMPL gets:
- Its own VMSA (VM Save Area) — one per vCPU per VMPL
- Separate RMP permissions — hardware-enforced memory isolation
- Separate ASID tracking (per-VMPL in multi-plane mode)

### AP Creation Across VMPLs

When the guest issues `SVM_VMGEXIT_AP_CREATE_*`:

```c
vmpl = get_ap_creation_vmpl(svm);              // extract from exit_info_1
target_plane = vcpu->kvm->planes[vmpl];        // get plane for that VMPL
target_vcpu = plane_get_vcpu(target_plane, apic_id);

// Security constraint: only VMPL0 can create VMPL0 vCPUs
if (vmpl == SVM_SEV_VMPL0 &&
    (vcpu == target_vcpu || vcpu->plane_level != SVM_SEV_VMPL0))
    return -EINVAL;
```

### VMPL Context Switching

```c
static int __sev_snp_run_vmpl(struct vcpu_svm *svm, unsigned int vmpl) {
    struct kvm_vcpu *target = vcpu->common->vcpus[vmpl];

    kvm_set_mp_state(target, KVM_MP_STATE_RUNNABLE);
    target_svm->sev_es.snp_ap_runnable = true;
    kvm_vcpu_set_plane_runnable(target);
    kvm_vcpu_set_plane_stopped(vcpu);

    kvm_make_request(KVM_REQ_PLANE_RESCHED, vcpu);
    return 1;  // VMPL context switch
}
```

---

## Shared vs Per-Plane Resources

| Resource | Scope |
|----------|-------|
| Guest physical address space (`kvm->memslots[]`) | Shared |
| I/O buses (MMIO/PIO) | Shared |
| `kvm_run` page | Shared (synchronized register transfer) |
| vCPU arrays | Per-plane |
| APIC state & IRQ routing | Per-plane |
| Memory attribute arrays | Per-plane |
| VMCS/VMCB (hardware VM state) | Per-plane (always separate) |
| All vCPU registers | Per-plane (cached via `kvm_sync_regs`) |
| FPU state & MMU contexts | Per-plane |
