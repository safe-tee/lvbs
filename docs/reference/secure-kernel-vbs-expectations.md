# Secure Kernel — Technical Expectations from VBS

This document describes what the **VBS (Virtualization-Based Security)** layer
expects of the **secure kernel** — the higher-privilege plane (plane‑1 / VTL1 /
VMPL0 / service TD) that protects a normal guest kernel (plane‑0 / VTL0 /
VMPL2+).

It is written from VBS's point of view: the contract the secure kernel must
honour so that the normal-plane `vbs_*()` API behaves correctly, regardless of
which transport backend (KVM software planes, SEV‑SNP VMPL/SVSM, Intel TDX
service TD, Hyper‑V VSM, Arm CCA) is active.

Reference implementation: the KVM software-planes secure monitor in
[`drivers/virt/secure_monitor.c`](../../linux/drivers/virt/secure_monitor.c)
and the transport-agnostic interface in
[`include/linux/vbs.h`](../../linux/include/linux/vbs.h).

---

## 1. Role and trust model

The secure kernel is a separate, higher-privilege execution context that shares
the VM but is isolated from the normal kernel. VBS expects it to be the **trust
anchor** for the normal plane:

- It can observe and restrict the normal plane's memory; the normal plane
  cannot observe or modify the secure kernel.
- It services security-policy requests (VTL calls) initiated by the normal
  plane and returns authoritative results.
- It is the only context permitted to grant or tighten EPT/NPT permissions on
  normal-plane pages.

The boundary is asymmetric **by construction**: a lower plane can never read up,
but a higher plane can read and restrict the plane directly below it.

---

## 2. Activation and identity

VBS does not hard-code the secure-plane index. The reference secure monitor is
activated by a kernel command-line switch and otherwise boots as an ordinary
kernel:

- **Opt-in only** — the `secure_monitor` early param enables the monitor. A
  kernel booted without it never parks and behaves as a normal guest.
- **Plane-agnostic** — the implementation refers to "the plane directly below
  the caller" rather than a fixed VTL/VMPL number, so the same code works as
  plane‑1 over plane‑0, or any higher plane over the one beneath it.
- **No full VBS stack required** — the secure monitor deliberately works
  without `CONFIG_VBS`/HEKI so a minimal kernel can act as the secure plane;
  richer policy handlers are layered in incrementally.

The secure-plane kernel is expected to be **uniprocessor**, to enter directly in
long mode, and to require no sub‑1M real-mode trampoline (it boots from a
carved-out high-memory region). See the trampoline-skip behaviour gated on
`CONFIG_VBS_SECURE_MONITOR`.

---

## 3. Lifecycle and the park/dispatch loop

VBS models all secure-kernel work as a request/response loop driven entirely by
the normal plane's `KVM_RUN`. The secure kernel is expected to:

1. Run its own early boot to a quiescent state.
2. **Seal its own memory** from the normal plane (Section 4) *before* handing
   control back the first time.
3. **Park** — return control to the normal plane and wait for the next request.
4. On each resume, **dispatch** the request named in the shared calling area,
   write the result, and park again.

```
normal plane                   KVM/transport                secure plane
------------                   -------------                ------------
fill calling area
HC_VBS_VTL_CALL(ca_gpa) ─────▶ switch_plane ──────────────▶ resume in park return
                               (RAX := ca_gpa)               dispatch(call_id)
                                                             write ca->status
resume after VTL_CALL ◀─────── switch_plane ◀────────────── HC_VBS_VTL_RETURN
```

Key expectation: the secure kernel **never runs on its own timeline**. It only
runs while the normal plane is suspended inside the hypercall that switched to
it. There is therefore no window in which secure-plane memory is both populated
and still readable by the normal plane.

---

## 4. Memory model expectations

All planes of a VM **share one guest-physical address space** (one set of
memslots). VBS relies on this for zero-copy request passing but it makes
self-protection mandatory:

- **Self-protection is the secure kernel's responsibility.** On startup it must
  walk its own system RAM and ask the transport to deny the normal plane
  read/write/exec on those ranges (`walk_system_ram_range` →
  `secmon_hide_range` → permissions `0`). Until it does, plane‑0 *can* read
  plane‑1 RAM.
- **The secure kernel cannot use the host ioctl path.** It does not issue
  `KVM_SET_MEMORY_ATTRIBUTES`. Instead it requests the attribute change via the
  `KVM_HC_VBS_SET_MEM_ATTRS` hypercall, which the transport honours **only for a
  higher-privilege plane** and applies to the plane directly below the caller.
- **Permission encoding is an allow-mask.** `perms` carries the access bits the
  lower plane should *retain* (`VBS_MEM_READ` / `VBS_MEM_WRITE` /
  `VBS_MEM_EXEC`). A cleared bit becomes `NO_READ` / `NO_WRITE` / `NO_EXEC`.
  `perms == 0` hides the range entirely.
- **`NO_READ` is fault-enforced.** Because "present but unreadable" is not
  expressible in EPT on all hardware, a `NO_READ` (or denied write) access by
  the lower plane is rejected in the fault path and exits to the VMM
  (`KVM_EXIT_MEMORY_FAULT`) rather than mapping the page. This is fail-closed:
  the offending read does **not** return secure-plane data.

VBS exposes this capability to the secure kernel as `protect_memory` /
`seal_kernel` and expects the secure kernel to apply it both to its own RAM and,
on request, to the normal plane's pages.

---

## 5. Calling-area ABI (wire contract)

The normal and secure planes communicate through a shared-memory **calling
area** whose layout is part of the ABI and must match on both sides
(`struct vbs_kvm_ca` in the monitor mirrors the producer in
`security/vbs/kvm_planes.c`):

| Field          | Type   | Set by    | Meaning                              |
| -------------- | ------ | --------- | ------------------------------------ |
| `call_pending` | `u8`   | caller    | 1 while a call is in flight          |
| `call_id`      | `u32`  | caller    | request id (`enum vbs_call_id`)      |
| `status`       | `s32`  | responder | return code (negative errno on fail) |
| `arg_size`     | `u32`  | caller    | request payload size                 |
| `resp_size`    | `u32`  | responder | response payload size                |
| `buffer[]`     | bytes  | both      | request in, response out             |

Expectations on the secure kernel:

- Map the calling area from the GPA delivered on resume, validate sizes, and
  **never trust `arg_size`/`resp_size` blindly** — treat the area as
  attacker-controlled input from a lower-privilege plane.
- Always write `status` and `resp_size`; `status` is authoritative even though a
  status value is also carried back on the park hypercall for tracing.

---

## 6. VTL-call dispatch responsibilities

VBS defines the request codes the secure kernel is expected to service
(`enum vbs_call_id`). Each maps to a normal-plane `vbs_*()` wrapper:

| Group              | Call code(s)                                              | Secure-kernel duty                                                |
| ------------------ | --------------------------------------------------------- | ----------------------------------------------------------------- |
| Core lifecycle     | `VBS_CALL_INIT`, `VBS_CALL_SHUTDOWN`                      | Track normal-plane boot/teardown                                  |
| Memory protection  | `VBS_CALL_PROTECT_MEMORY`, `VBS_CALL_SEAL_KERNEL`         | Enforce page perms on lower plane; make its text/rodata immutable |
| Module auth        | `VBS_CALL_VALIDATE_MODULE`, `…_SET_MODULE_PERMS`, `…_UNLOAD_MODULE` | Verify signatures, set per-section EPT (text=RX, rodata=R, data=RW), release on unload |
| Key / certificate  | `VBS_CALL_ADD_KEY`, `VBS_CALL_REVOKE_KEY`, `VBS_CALL_SEND_CERTS` | Manage runtime keys and the trusted cert set                      |
| Kexec validation   | `VBS_CALL_KEXEC_VALIDATE`, `VBS_CALL_KEXEC_INVALIDATE`    | Validate/invalidate a kexec target kernel                         |

Behavioural expectations:

- **Authoritative enforcement.** When the normal plane calls
  `vbs_seal_kernel()` it expects that, afterwards, any write to its kernel text
  from the lower plane traps to the secure kernel. The decision must be made and
  enforced in the secure plane, not advisory.
- **Fail-closed semantics.** Unverifiable module signatures, malformed requests,
  or unsupported calls must return a negative errno and must not relax any
  protection.
- **Forward-compatible no-ops.** An un-plumbed handler may acknowledge a call as
  a no-op so the normal plane can make progress, but it must never *grant* a
  protection it did not actually apply.

---

## 7. Transport-agnostic backend contract

VBS is transport-agnostic; the secure kernel's duties are the same across
backends, only the wire encoding differs:

| Backend            | Transport to the secure kernel                              |
| ------------------ | ----------------------------------------------------------- |
| KVM software planes | Hypercall 15 `KVM_HC_VBS_VTL_CALL` → VMM → plane‑1 vCPU      |
| SEV‑SNP VMPL/SVSM  | `VMGEXIT` → SVSM CAA protocol (Protocol 3) → VMPL0           |
| Intel TDX service TD | Shared-memory IPC to a separate TD (future)               |
| Hyper‑V VSM        | Native VTL hypercalls                                        |
| Arm CCA            | RSI host calls from Realm guest to RMM                       |

Regardless of transport, the secure kernel must implement the same observable
behaviour: park/dispatch loop, self-protection, allow-mask permission semantics,
and fail-closed policy enforcement. Backends advertise which `vbs_ops`
callbacks they implement; an unimplemented feature returns `-ENOTSUP`/`-ENOSYS`
rather than silently succeeding.

---

## 8. Security invariants (summary)

The secure kernel must uphold, at all times:

1. **No read-up.** The normal plane can never read or write secure-kernel
   memory; this is sealed before control is first returned and stays sealed.
2. **Higher-only attribute changes.** Memory-attribute requests are honoured
   only from a higher-privilege plane and only affect the plane directly below.
3. **Fail-closed.** Denied accesses fault out to the VMM; failed or unsupported
   requests tighten or preserve protection, never loosen it.
4. **Untrusted input.** The calling area and all GPAs it references come from a
   lower-privilege plane and are validated before use.
5. **No independent timeline.** The secure kernel runs only while the normal
   plane is suspended in the switch hypercall, eliminating
   populated-but-readable races.

---

## 9. Current implementation status

The reference KVM secure monitor today:

- ✅ Activates on `secure_monitor`, runs as a `vbs-secmon` kthread.
- ✅ Seals all of its own system RAM from the normal plane on startup
  (`secmon_protect_self`), proven by the plane read-isolation test.
- ✅ Implements the park/dispatch loop and the calling-area ABI.
- ⏳ Acknowledges VTL calls as no-ops; per-call policy handlers (HEKI memory
  protection, kernel sealing, module auth, keys, kexec) are being added
  incrementally.

See also: [vm-planes-vbs-backends.md](vm-planes-vbs-backends.md),
[vm-planes-data-structures.md](vm-planes-data-structures.md), and
[lvbs-boot-process.md](lvbs-boot-process.md).
