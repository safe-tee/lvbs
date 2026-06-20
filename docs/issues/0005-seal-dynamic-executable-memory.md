# 0005 — Seal dynamically-allocated executable memory

- **Status:** Open
- **Area:** execmem / modules
- **Depends on:** #0002
- **Blocks:** #0007 (partial)

## Problem

Not all executable code is part of static `_stext.._etext`. Several subsystems
allocate **new** executable pages at runtime:

- ftrace per-ops trampolines (`arch_ftrace_update_trampoline`, via execmem +
  `text_poke_copy`)
- optimized-kprobe instruction slots
- module text
- BPF JIT images

After the kernel is sealed, these must not become a write-and-execute hole for
the normal plane.

## Proposal

Adopt an **allocate → populate → validate → seal RX → execute** lifecycle for
all runtime executable allocations:

- Extend the secure plane's protection machinery (`secmon_apply_attrs` /
  `VBS_CALL_SET_MODULE_PERMS`-style call) to flip newly populated exec regions
  to RX from the normal plane's perspective once relocation/patching is done.
- Post-seal writes into these regions go through the mediated poke (#0001/#0002).
- For module text, integrate with `VBS_CALL_VALIDATE_MODULE` /
  `VBS_CALL_SET_MODULE_PERMS` (text=RX, rodata=R, data=RW).
- **BPF JIT decision:** choose one — mediate JIT writes, validate the JITed
  image before sealing, or disallow JIT under VBS. Document the choice.

## Acceptance criteria

- [ ] ftrace dynamic trampolines are sealed RX after population and still
      callable.
- [ ] A post-seal write into a sealed exec region from the normal plane is
      denied (faults out) unless mediated.
- [ ] Module text/rodata/data get correct per-section perms via VBS.
- [ ] BPF-JIT-under-VBS policy decided and enforced.

## Notes

This is the part ftrace needs beyond call-site patching: the global/per-ops
trampolines live in dynamically allocated exec memory, not static text.
