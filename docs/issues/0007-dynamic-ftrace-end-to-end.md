# 0007 — Dynamic ftrace end-to-end against a sealed kernel (tracking)

- **Status:** Open
- **Area:** tracking / demo
- **Depends on:** #0002, #0003, #0004, #0006 (and #0005 for trampolines)

## Goal

Prove the narrowest useful end-to-end slice: with kernel text sealed by the
secure plane, **dynamic ftrace** can still enable/disable a tracer on the normal
plane, with all text writes mediated and validated.

This is the integration/tracking issue tying together the mediated-poke work.

## Plan (smallest viable slice first)

1. Land the primitive hook + `VBS_CALL_POKE_TEXT` (#0002, #0003).
2. Minimal validation allowlist: fentry NOP ↔ `call rel32` only (#0004).
3. Correct boot ordering so the seal lands after boot patching (#0006).
4. Seal the ftrace trampoline exec memory (#0005) so calls land in RX pages.
5. Demonstrate `echo function > current_tracer` (and back to `nop`) on the
   sealed normal plane; confirm traces appear and the seal stays intact.

## Acceptance criteria

- [ ] With the kernel sealed, enabling the `function` tracer succeeds via
      mediated pokes (no direct writes to sealed text).
- [ ] Disabling the tracer restores the original NOPs via mediation.
- [ ] An attempt to poke a non-allowlisted shape is rejected by the secure plane.
- [ ] A guest-side test (sibling of `test-plane-read-isolation.sh`) automates the
      enable/trace/disable check.

## Fallback

If full mediation is not yet ready, the interim posture is to **disable runtime
text patching under VBS** (no dynamic ftrace/kprobes/BPF-JIT; only boot-time
patching before the seal). This preserves the security boundary at the cost of
tracing/probing/JIT and should be replaced by the mediated path.
