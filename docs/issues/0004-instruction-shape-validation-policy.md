# 0004 — Instruction-shape validation policy in the secure plane

- **Status:** Open
- **Area:** secure-plane policy
- **Depends on:** #0002
- **Blocks:** #0007

## Problem

A mediated text-poke handler that blindly memcpy's attacker-supplied bytes into
kernel text would defeat the seal entirely. The secure plane must only allow
patches whose **shape** matches a known, legitimate runtime-patching pattern,
and only at valid targets.

## Proposal

In the secure-plane handler, before applying any poke:

1. **Target check** — the destination must lie within sealed kernel text or a
   registered trampoline/execmem region (#0004); reject everything else.
2. **Shape allowlist** — accept only known transitions:
   - fentry NOP `0f 1f 44 00 00` ↔ `call rel32` to a known ftrace trampoline
   - `0xCC` (INT3) at a kprobe site
   - jump-label NOP ↔ `jmp rel32`
   - static-call `call/jmp rel32` to an allowed target
   - boot alternatives (if any post-seal) — likely disallow
3. **Reject** arbitrary overwrites (e.g. replacing a function prologue with
   attacker code) with a negative errno.
4. *(Optional)* measure/hash the resulting text region for attestation.

## Acceptance criteria

- [ ] Handler validates target range and instruction shape before writing.
- [ ] Allowlisted transitions for ftrace are accepted; a non-conforming write is
      rejected with an errno and leaves text unchanged.
- [ ] Policy is data-driven enough to extend to kprobes/jump-labels/static-calls
      without structural rework.

## Notes

Mirrors the role of Windows HVCI's secure-kernel patch validation. Start with
the fentry nop↔call pair (enough for #0006), widen incrementally.
