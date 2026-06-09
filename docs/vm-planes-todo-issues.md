# VM Planes Implementation — Open Issues

Tracking TODO/FIXME items discovered in the `vm-planes` branch of the Linux kernel KVM subsystem.

---

## Issue 1: Allow SNP to use VM Planes for Virtual Trust Levels (VTPLs)

**File:** `arch/x86/kvm/x86.c` (line 14536)
**Labels:** `enhancement`, `kvm`, `sev-snp`, `vm-planes`

### Description

`kvm_arch_nr_vcpu_planes()` currently hard-codes VMs with protected state to a single plane:

```c
int kvm_arch_nr_vcpu_planes(struct kvm *kvm)
{
	/* TODO: use kvm_x86_ops so that SNP can use planes for VTPLs. */
	return kvm->arch.has_protected_state ? 1 : KVM_MAX_VCPU_PLANES;
}
```

This blocks AMD SEV-SNP from using VM Planes to implement Virtual Trust Levels (VTPLs / VMPLs). TDX VMs also have `has_protected_state` set, but TDX doesn't currently use planes for its own purposes.

### Proposed Fix

Introduce a `kvm_x86_ops` callback (e.g., `.nr_vcpu_planes()`) so that each vendor backend can independently decide how many planes to expose. The SNP backend would return `KVM_MAX_VCPU_PLANES` to enable VMPL-based trust levels, while TDX would return 1 (or more, if service-TD planes are supported later).

---

## Issue 2: Handle page-boundary-splitting MMIO in SEV-ES emulated MMIO path

**File:** `arch/x86/kvm/x86.c` (line 14608)
**Labels:** `bug`, `kvm`, `sev-es`

### Description

In `kvm_sev_es_mmio()`, when a partially-handled MMIO request spans a page boundary, the remaining bytes are forwarded to userspace without checking whether this is well-defined behavior:

```c
	/*
	 * TODO: Determine whether or not userspace plays nice with MMIO
	 *       requests that split a page boundary.
	 */
	frag = vcpu->mmio_fragments;
	frag->len = bytes;
	frag->gpa = gpa;
```

If userspace (e.g., QEMU) does not handle cross-page MMIO fragments correctly, this could cause silent data corruption or MMIO emulation failures.

### Proposed Fix

Audit the userspace MMIO handling to confirm cross-page fragments are supported. If not, either split the request into per-page fragments or reject cross-page MMIO with an error.

---

## Issue 3: TDX Secure EPT — Add large page (hugepage) support for private memory mapping

**File:** `arch/x86/kvm/vmx/tdx.c` (lines 1664, 1796)
**Labels:** `enhancement`, `kvm`, `tdx`

### Description

Both `tdx_sept_set_private_spte()` and `tdx_sept_zap_private_spte()` assert `level == PG_LEVEL_4K` and BUG on anything larger:

```c
/* TODO: handle large pages. */
if (KVM_BUG_ON(level != PG_LEVEL_4K, kvm))
    return -EIO;
```

This limits all TDX private memory to 4K pages, which has significant performance implications for memory-intensive workloads due to increased TLB pressure and SEPT walk depth.

**Affected functions:**

| Function | Line | Operation |
|---|---|---|
| `tdx_sept_set_private_spte()` | 1664 | Mapping/adding pages |
| `tdx_sept_zap_private_spte()` | 1796 | Removing/blocking pages |

### Proposed Fix

Implement 2M (and optionally 1G) page support using `TDH.MEM.PAGE.ADD` / `TDH.MEM.PAGE.AUG` with the appropriate TDX SEPT level parameter. The zap path needs corresponding `TDH.MEM.RANGE.BLOCK` + `TDH.MEM.PAGE.REMOVE` support at higher levels. This also depends on guest_memfd hugepage support (Issue #5).

**Depends on:** Issue #5 (guest_memfd hugepage support)

---

## Issue 4: TDX CPUID metadata read should check for specific TDX error codes

**File:** `arch/x86/kvm/vmx/tdx.c` (line 2608)
**Labels:** `bug`, `kvm`, `tdx`

### Description

In the TDX CPUID configuration read path, the error from `tdx_td_metadata_field_read()` is treated as a single opaque failure:

```c
err = tdx_td_metadata_field_read(kvm_tdx, field_id, &ebx_eax);
if (err) //TODO check for specific errors
    goto err_out;
```

Different TDX module error codes (e.g., `TDX_METADATA_FIELD_NOT_READABLE`, `TDX_OPERAND_INVALID`, `TDX_OPERAND_BUSY`) have different semantics. Some may indicate a retryable condition, an unsupported field (which could be handled gracefully), or a genuine error.

### Proposed Fix

Check the specific TDX error code returned by `tdx_td_metadata_field_read()` and handle each case appropriately:

- **Unsupported/non-existent field** → return zeroed CPUID output or skip gracefully
- **Operand busy** → retry
- **Other errors** → error out as today

---

## Issue 5: guest_memfd — Add hugepage support

**File:** `virt/kvm/guest_memfd.c` (line 122)
**Labels:** `enhancement`, `kvm`, `guest-memfd`

### Description

`kvm_gmem_get_folio()` is limited to order-0 (4K) folios:

```c
static struct folio *kvm_gmem_get_folio(struct inode *inode, pgoff_t index)
{
	/* TODO: Support huge pages. */
```

The code further notes that internal handling assumes all folios are order-0 and that operations like page-clearing would need updates for larger pages.

This is a prerequisite for efficient TDX private memory and VM Planes private memory in general. Without hugepage support, all private memory mapped through guest_memfd incurs 4K TLB granularity overhead.

### Proposed Fix

Extend `kvm_gmem_get_folio()` to allocate and manage compound folios (order-9 for 2M, order-18 for 1G). Update all internal page-clearing, migration, and invalidation paths to handle non-order-0 folios. Coordinate with the TDX SEPT large-page support (Issue #3).

---

## Issue 6: Remove WARN on guest_memfd memslot unbind once dirty logging is supported

**File:** `virt/kvm/kvm_main.c` (line 1791)
**Labels:** `cleanup`, `kvm`, `guest-memfd`

### Description

In the memslot update path, a `WARN_ON_ONCE` fires if a guest_memfd-backed memslot undergoes a flags-only change (which would only happen with dirty logging):

```c
		/*
		 * Unbind the guest_memfd instance as needed; the @new slot has
		 * already created its own binding.  TODO: Drop the WARN when
		 * dirty logging guest_memfd memslots is supported.  Until then,
		 * flags-only changes on guest_memfd slots should be impossible.
		 */
		if (WARN_ON_ONCE(old->flags & KVM_MEM_GUEST_MEMFD))
			kvm_gmem_unbind(old);
```

Once dirty logging for guest_memfd memslots is implemented, this WARN should be converted to normal control flow.

### Proposed Fix

When dirty logging support for guest_memfd is added, replace the `WARN_ON_ONCE` with proper handling of the memslot rebinding.
