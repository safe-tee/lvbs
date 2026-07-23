# 0003 — Route x86 text-poke primitives through VBS when sealed

- **Status:** Open
- **Area:** x86 / alternatives
- **Depends on:** #0002
- **Blocks:** #0007

## Problem

Nearly all x86 runtime text patching funnels through a few primitives in
[arch/x86/kernel/alternative.c](../../../linux/arch/x86/kernel/alternative.c):

- `__text_poke()` → `text_poke()`, `text_poke_copy()`, `text_poke_set()`
  (uses the `text_poke_mm` temporary writable alias)
- `smp_text_poke_single()` and the INT3 batch path

If these are mediated once, the higher-level consumers (ftrace, kprobes,
jump labels, static calls) are covered automatically.

## Proposal

- When `vbs_available()` and the target lies in sealed text, branch the
  primitive to the `vbs_poke_text()` path (#0001) instead of writing via the
  temporary mm.
- Handle the live-patch INT3 protocol (write `0xCC` → sync → write tail → write
  head): each step writes text, so each must be mediated. Submit the whole batch
  in one VTL call to amortize the plane-switch cost.
- Leave `text_poke_early()` (pre-seal, boot) writing directly.
- Gate all of this on the VBS config so non-VBS kernels are unaffected.

## Acceptance criteria

- [ ] `__text_poke`, `text_poke_copy/set`, `smp_text_poke_single`, and the INT3
      batch route through VBS when the target is sealed.
- [ ] A single `text_poke_bp` on a sealed call site succeeds via mediation.
- [ ] No direct write to sealed text remains on the post-seal path.
- [ ] Non-VBS / pre-seal paths behave exactly as before.

## Notes

Performance: the INT3 batch interface already batches; preserve that batching
across the VBS boundary rather than one VTL call per site.
