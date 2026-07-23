# LVBS Issues

Locally tracked issues for the LVBS / VM-planes work, one markdown file per
issue, numbered sequentially (`NNNN-short-title.md`).

## Open

| #    | Title                                                                 | Area            |
| ---- | --------------------------------------------------------------------- | --------------- |
| 0001 | [Validate module signatures in the secure plane with plane-local keys](0001-secure-plane-module-signature-key-custody.md) | secure-plane key custody |
| 0002 | [Mediated text-poke VTL call (`VBS_CALL_POKE_TEXT`)](0002-mediated-text-poke-vtl-call.md) | secure-plane ABI |
| 0003 | [Route x86 text-poke primitives through VBS when sealed](0003-route-text-poke-primitives-through-vbs.md) | x86 / alternatives |
| 0004 | [Instruction-shape validation policy in the secure plane](0004-instruction-shape-validation-policy.md) | secure-plane policy |
| 0005 | [Seal dynamically-allocated executable memory](0005-seal-dynamic-executable-memory.md) | execmem / modules |
| 0006 | [Enforce boot-time patch ordering before `SEAL_KERNEL`](0006-boot-time-patch-ordering.md) | boot sequence |
| 0007 | [Dynamic ftrace end-to-end against a sealed kernel (tracking)](0007-dynamic-ftrace-end-to-end.md) | tracking / demo |

## Theme: secure-plane key custody & module authentication

Issue **0001** moves all module-authentication trust roots (and any private key
material) into the secure plane so verification happens entirely there with
plane-local keys; plane 0 can read public keys but never private ones.

## Theme: protecting runtime kernel text patching under VBS

Once `VBS_CALL_SEAL_KERNEL` makes kernel text immutable, the seal is enforced at
the EPT/physical level by the secure plane, covering every GVA alias — including
the temporary writable alias `__text_poke()` builds in `text_poke_mm`. Every
legitimate runtime text patcher (ftrace, kprobes, static keys/jump labels,
static calls, BPF JIT, module loading) therefore breaks unless its writes are
mediated through the secure plane. Issues **0002–0007** break that work down.
