# LVBS (Hyper-V VSM) vs VM Planes (KVM) — Kernel Loading Comparison

Comparing how the secure kernel (VTL1 / Plane 1) is loaded and booted in each approach.

---

## What's the Same

Both approaches have the **guest kernel (VTL0 / Plane 0) load the secure kernel image**:
- Both read a `vmlinux.bin` / `vmlinux` file using `filp_open()` + `kernel_read()` from within the running kernel
- Both copy the image into pre-allocated memory
- Both build `boot_params` (zero-page) with e820 map, cmdline, and standard Linux boot protocol fields

---

## Key Differences

| Aspect | LVBS (`hv_vsm_boot.c`) | VM Planes (`init/vm_planes.c` + QEMU) |
|--------|----------------------|---------------------------------------|
| **Image format** | Raw binary (`vmlinux.bin` via `objcopy`). Single `memcpy` at a fixed offset (`VSM_SKERNEL_OFFSET = 2MB`) | Full ELF (`vmlinux`). Parses ELF headers, iterates `PT_LOAD` segments, copies each independently with `copy_to_early_mem()` |
| **Memory allocation** | VTL0 kernel reserves memory at boot via `memblock_reserve()` (`hv_vsm_reserve_sk_mem`). Memory is at a fixed physical region (`sk_res`) | QEMU allocates a new RAM region dynamically via `memory_region_init_ram()` + `KVM_SET_USER_MEMORY_REGION` after HC 13 hypercall |
| **Copy method** | Direct `memcpy()` into `vsm_skm_va` (a `vmap` of the reserved physical pages) | `copy_to_early_mem()` using `early_memremap()` page-by-page (since the plane memory is outside the kernel's direct map) |
| **Entry point** | Fixed: `VSM_VA_FROM_PA(vsm_skm_pa) + VSM_SKERNEL_OFFSET` — always at the 2MB offset | Computed from ELF `e_entry`, translated from virtual to physical via segment `p_vaddr`/`p_paddr` mapping, biased by `load_offset` |
| **Boot params setup** | VTL0 kernel builds `boot_params` directly in `vsm_build_boot_params()` within the reserved memory region | QEMU builds boot_params, page tables, and GDT in plane-1 memory during HC 14 handling — the guest never touches these |
| **Page tables / GDT** | Not needed — Hyper-V hypervisor sets up VTL1 vCPU context via `hv_init_vp_context` (CR3, segments, etc.) | QEMU must write identity-mapped page tables (PML4→PDPT→PD) and a GDT into plane-1 RAM because KVM doesn't provide the vCPU context setup that Hyper-V does |
| **vCPU activation** | VTL call (`hv_vsm_init_vtlcall`) — Hyper-V switches execution context to VTL1 | QEMU sets `KVM_SET_SREGS` / `KVM_SET_REGS` / `KVM_SET_MP_STATE` then spawns a thread calling `KVM_RUN` |
| **Signature verification** | Built-in: reads `.p7s` signature file, verifies via `verify_vsm_signature()` before loading | Not implemented yet — no signature verification in the VM planes path |
| **Loader** | Originally had a separate `skloader.bin`; commit `901aa63` eliminates it and boots the kernel directly | No intermediate loader — boots the kernel directly from the start |

---

## Memory Layout

### LVBS (Hyper-V VSM)

```
vsm_skm_pa (reserved via memblock_reserve)
├── 0x0000  BOOTPARAMS (4KB)    ← boot_params struct (zero-page)
├── 0x1000  CMDLINE (512B)      ← kernel command line
├── 0x200000 (2MB)  SKERNEL     ← vmlinux.bin copied here (16MB+)
└── end of sk_res
```

### VM Planes (KVM + QEMU)

```
load_offset (RAM allocated by QEMU via memory_region_init_ram)
├── ELF PT_LOAD segments         ← copied by plane-0 kernel via early_memremap
├── ...
├── top - 0x10000  Page tables   ← written by QEMU (PML4, PDPT, PD)
├── top - 0x4000   GDT           ← written by QEMU
├── top - 0x2000   boot_params   ← written by QEMU (zero-page)
├── top - 0x1000   cmdline       ← written by QEMU
└── top (load_offset + memory_size)  ← initial RSP
```

---

## Boot Sequence Comparison

### LVBS

1. VTL0 kernel reserves memory (`memblock_reserve`)
2. VTL0 reads `vmlinux.bin` from `/usr/lib/firmware/` via VFS
3. Optionally verifies PKCS#7 signature (`.p7s`)
4. `memcpy` into reserved region at 2MB offset
5. VTL0 builds `boot_params` in the reserved region
6. VTL0 calls `hv_vsm_init_vtlcall()` — Hyper-V switches to VTL1
7. Hyper-V sets up VTL1 vCPU context (CR0/CR3/CR4/EFER, segments, RIP)
8. VTL1 kernel starts executing

### VM Planes

1. Plane-0 kernel parses `/config-vm-planes` from initrd
2. Plane-0 issues HC 13 hypercall → exits to QEMU
3. QEMU creates KVM plane (`KVM_CREATE_PLANE`), allocates RAM, creates vCPUs
4. Returns to plane-0 guest
5. Plane-0 reads `vmlinux` ELF from initrd, copies PT_LOAD segments via `early_memremap`
6. Plane-0 issues HC 14 hypercall → exits to QEMU
7. QEMU writes page tables, GDT, boot_params, cmdline into plane-1 RAM
8. QEMU sets vCPU registers (`KVM_SET_SREGS`/`KVM_SET_REGS`)
9. QEMU spawns vCPU thread with `KVM_RUN`
10. Plane-1 kernel starts executing

---

## Summary

The LVBS approach is simpler because **Hyper-V provides rich VSM primitives** — VTL memory isolation is hardware-enforced, VTL call gives a direct context switch, and the hypervisor sets up the VTL1 vCPU state. The VM planes approach has to **replicate much of this in QEMU userspace** (page tables, GDT, register initialization) because KVM's plane support only provides the vCPU/memory isolation primitives, not a full boot protocol. The ELF loading in VM planes is more flexible than LVBS's raw binary copy, but LVBS has signature verification that VM planes currently lacks.
