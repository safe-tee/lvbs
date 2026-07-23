# LVBS Boot: VTL0 Loads and Verifies VTL1 Secure Kernel

## 1. Purpose and Security Goal

This document defines a boot architecture in which **Virtual Trust Level 1 (VTL1, VM Plane 1)** — the secure, higher‑privileged kernel — is **established as the root security authority before the system enters an attack‑exposed phase**, while preserving compatibility with **UEFI, systemd‑stub, Unified Kernel Images (UKI), and upstream Linux workflows**.

Although a minimal portion of **VTL0 kernel code executes first**, this execution occurs **before `init`, before unverified userspace, and under Secure Boot guarantees**. VTL0 is therefore treated strictly as a **trusted loader**, not as the security authority. Control authority is transferred to VTL1 before the system reaches a state where kernel compromise is assumed.

This satisfies the LVBS requirement:

> **VTL1 must be authenticated and established before VTL0 is allowed to execute freely.**

---

## 1.1 Terminology: VTLs and VM Planes

To keep the design portable across hypervisors and upstream ecosystems, this document uses **Virtual Trust Levels (VTLs)** together with the more general **VM Planes** abstraction.

| Concept | Meaning |
|-------|---------|
| **VTL0 (VM Plane 0)** | Default / guest execution environment where the primary Linux kernel and userspace run |
| **VTL1 (VM Plane 1)** | Higher‑privileged, isolated execution environment used for the secure kernel |

**Key points**

- **VTLs are a specific realization of the VM Planes concept**, originally defined by Hyper‑V but applicable to other hypervisors (e.g., KVM).
- **Plane 0 / VTL0** is treated as potentially compromised after early boot.
- **Plane 1 / VTL1** establishes and enforces system‑wide security policy and integrity guarantees.

Throughout this document, the terms are used together (for example, *VTL1 / VM Plane 1*) to remain clear and upstream‑friendly.

---

## 2. High‑Level Boot Sequence

The effective order of **trust establishment** (not raw instruction execution) is:

1. **UEFI Secure Boot / TPM Root of Trust**
2. **Authentication and launch of the VTL1 secure kernel**
3. **Release of the VTL0 kernel under VTL1 supervision**

### Execution Flow

```text
UEFI Firmware
  → systemd-stub (UKI)
    → Linux kernel entry (VTL0 – early boot only)
      → Hypervisor enables VTLs / VM planes
        → VTL0 verifies VTL1 payload
          → Enter VTL1 and boot secure kernel
            → VTL1 applies immutable protections
              → Resume VTL0 and allow init
