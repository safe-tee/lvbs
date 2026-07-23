# 0006 — Enforce boot-time patch ordering before `SEAL_KERNEL`

- **Status:** Open
- **Area:** boot sequence
- **Depends on:** —
- **Blocks:** #0007

## Problem

Many kernel text patches happen **once** at boot: alternatives, paravirt
patching, jump-label init, and ftrace's initial nop-ification (`ftrace_init`).
These must all complete *before* `VBS_CALL_SEAL_KERNEL`; otherwise either the
seal captures un-patched text, or the boot-time patcher hits a sealed region and
fails.

## Proposal

- Establish a well-defined watershed: all one-time boot patching runs first,
  then `seal_kernel`, after which only the mediated poke path (#0001/#0002) may
  modify text.
- Audit the init order so `VBS_CALL_SEAL_KERNEL` is issued after
  `apply_alternatives`, paravirt patching, `jump_label_init`, and the initial
  ftrace conversion.
- Add a guard/warning if any direct (non-mediated) text write is attempted after
  the seal, to catch ordering regressions early.

## Acceptance criteria

- [ ] Documented ordering: boot patching → seal → mediated-only.
- [ ] `seal_kernel` is demonstrably issued after all one-time boot patching.
- [ ] A direct post-seal text write is detected (warn/deny) rather than silently
      faulting somewhere obscure.

## Notes

This is the cheap-but-essential prerequisite; without correct ordering the more
complex mediation work (#0001–#0004) can't be validated cleanly.
