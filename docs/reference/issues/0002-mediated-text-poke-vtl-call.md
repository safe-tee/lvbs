# 0002 — Mediated text-poke VTL call (`VBS_CALL_POKE_TEXT`)

- **Status:** Open
- **Area:** secure-plane ABI
- **Depends on:** `VBS_CALL_SEAL_KERNEL`
- **Blocks:** #0003, #0007

## Problem

After the kernel text is sealed, the normal plane can no longer write its own
text — the seal is enforced at the EPT/physical level, so even the temporary
writable alias `__text_poke()` builds in `text_poke_mm`
([arch/x86/kernel/alternative.c](../../../linux/arch/x86/kernel/alternative.c))
is denied. To keep legitimate runtime patching (ftrace, kprobes, jump labels,
static calls) working, those writes must be delegated to the secure plane, which
is the only context with write access to the sealed pages.

## Proposal

Add a mediated text-poke request to the VBS ABI:

- New `VBS_CALL_POKE_TEXT` in `enum vbs_call_id`
  ([include/linux/vbs.h](../../../linux/include/linux/vbs.h)).
- Normal-plane wrapper `vbs_poke_text(addr, opcode, len)` and a `vbs_ops`
  callback.
- Calling-area payload: target GPA (or list of GPAs for a batch), new opcode
  bytes, length. Support a **batch** form so a multi-site patch (e.g. the INT3
  live-patch dance, or enabling ftrace across many call sites) is one VTL call.
- Secure-plane handler in
  [drivers/virt/secure_monitor.c](../../../linux/drivers/virt/secure_monitor.c):
  validate (see #0003), perform the write itself, re-establish the seal, return
  status.

## Acceptance criteria

- [ ] `VBS_CALL_POKE_TEXT` defined; normal-plane wrapper + backend op present.
- [ ] Secure-plane handler applies a single-page poke and returns 0 on success,
      negative errno on rejection.
- [ ] Batch form carries N (gpa, bytes) entries in one call.
- [ ] Treats the calling area / sizes as untrusted input.

## Notes

This is the previously deferred "bring the poke later" work. Keep the validation
policy itself in #0003 so this issue is just the transport/ABI.
