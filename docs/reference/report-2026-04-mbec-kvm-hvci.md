# Current Status of Linux KVM Intel MBEC / AMD GMET Support- **SVM** (`arch/x86/kvm/svm/`) – AMD virtualization
- **KVM MMU** (`arch/x86/kvm/mmu/`) – shadow/nested page tables

### Mailing Lists
- `kvm@vger.kernel.org` — KVM subsystem
- `linux-kernel@vger.kernel.org` — broader kernel review
- `x86@kernel.org` — x86 architecture maintainers

### Key Contributors
- **Paolo Bonzini** (Red Hat) — KVM maintainer; combined MBEC/GMET series
- **Sean Christopherson** (Google) — KVM co‑maintainer; deep technical reviews
- **Jon Kohler** (Nutanix) — original MBEC RFC and v1 series
- **Mickaël Salaün** — earlier MBEC work (Heki); reviewer
- **Amit Shah** — AMD GMET analysis
- **Chao Gao** — Intel-side review feedback

---

## 3. Timeline of Upstream Activity

### 2023: Prior Art (Heki)
- Mickaël Salaün posts early MBEC support as part of **Heki** (RFC v1 in May 2023; RFC v2 in Nov 2023).

### March 13, 2025: Jon Kohler RFC (00/18)
- **Intel MBEC for KVM/VMX** posted as an 18‑patch RFC.
- Demonstrates large HVCI performance gains.
- Tested on Linux **6.12‑based** kernels; Windows 11/Server guests.

### April–May 2025: Reviews
- Mickaël Salaün: generally positive, requests clarifications.
- Sean Christopherson: extensive review; flags design bugs (per‑vCPU tracking), demands **KVM unit tests** and structural changes.

### December 22, 2025: Jon Kohler v1 (PATCH 0/8)
- Reduced to **8 patches**.
- Addresses review feedback: moves enablement to **MMU role**, removes module params, adds unit tests.
- Tested on **6.18‑based** kernels.
- QEMU and kvm‑unit‑tests branches published.

### March 21, 2026: Paolo Bonzini RFC (00/22)
- **Combined Intel MBEC + AMD GMET** series.
- Refactors MMU permissions; enables MBEC/GMET even in non‑nested mode to simplify logic.
- Smaller net diff despite supporting both vendors.

### March 26, 2026: Paolo Bonzini RFC v2 (00/24)
- Expanded to **24 patches**.
- Requires **advanced EPT violation vmexit info** for nested MBEC.
- Fixes found via kvm‑unit‑tests; drops `gmet` from `/proc/cpuinfo`.
- States confidence in design but keeps RFC status pending more testing.

### March 30 – April 1, 2026: Follow‑ups
- **Tested‑by** from Jon Kohler.
- Paolo identifies a bug in `translate_nested_gpa` (GMET always allowing exec) and lists **7 additional fixes** needed (NX huge pages, permission checks, CPL handling, cleanup ordering).

---

## 4. Current Status (April 2026)

- **Not merged** into mainline Linux.
- Latest state: **RFC v2 (24 patches)**, under active review.
- Maintainer confidence in architecture is high, but **known bugs remain**.
- **QEMU**: underlying MBEC/GMET support exists, but features are **not yet exposed via CPU model definitions**, blocking easy end‑to‑end use.

---

## 5. Open Issues

### Kernel (KVM/MMU)
- `translate_nested_gpa` incorrectly sets `PFERR_USER_MASK` for GMET.
- NX huge page handling with user‑execute masks on AMD.
- Missing XU handling in some permission checks.
- Correct CPL handling for GMET.
- Patch ordering / cleanup for bisectability.
- Conditional enabling of nested MBEC/GMET.

### Testing
- Continued validation across Intel/AMD, nested and non‑nested paths.
- Ensuring all MBEC/GMET permutations are covered by kvm‑unit‑tests.

### QEMU
- CPU model definitions not yet advertising MBEC/GMET.
- Users cannot enable MBEC with standard `-cpu` flags (tracked in QEMU issue #3099).

---

## 6. Likely Next Steps

1. **Revised patchset (v3)** from Paolo Bonzini incorporating identified fixes.
2. **QEMU patches** to expose MBEC/GMET in CPU models.
3. Exit RFC status after review/testing, targeting a **future kernel merge window**.
4. Coordinated kernel + QEMU enablement for practical HVCI acceleration.

---

## 7. References

1. Jon Kohler, **[RFC PATCH 00/18] KVM: VMX: Introduce Intel Mode‑Based Execute Control (MBEC)**  
   https://lwn.net/Articles/1014190/

2. Mickaël Salaün, review of MBEC RFC (Apr 15, 2025)  
   https://lkml.iu.edu/2504.1/11667.html

3. Sean Christopherson, detailed RFC review (May 12, 2025)  
   https://www.spinics.net/lists/kernel/msg5681442.html

4. Jon Kohler, **[PATCH 0/8] KVM: VMX: Introduce Intel MBEC (v1)** (Dec 22, 2025)  
   https://www.spinics.net/lists/kernel/msg5977244.html

5. Paolo Bonzini, **[RFC PATCH 00/22] KVM: combined patchset for MBEC/GMET** (Mar 21, 2026)  
   https://lwn.net/Articles/1064171/

6. Paolo Bonzini, **[RFC PATCH v2 00/24] KVM: combined patchset for MBEC/GMET** (Mar 26, 2026)  
   https://lkml.org/lkml/2026/3/26/1960

7. Paolo Bonzini & Jon Kohler, follow‑ups and bug discussion (Mar 30, 2026)  
   https://lkml.org/lkml/2026/3/30/886

8. Paolo Bonzini, additional fixes discussion (Apr 1, 2026)  
   https://lkml.org/lkml/2026/4/1/1745

9. QEMU Issue #3099, **“QEMU does not properly pass‑through hardware MBEC support”**  
   https://gitlab.com/qemu-project/qemu/-/issues/3099

10. Microsoft Docs, **Memory Integrity / HVCI**  
    https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity


**Report Date:** April 2026

---

## 1. Introduction

**KVM support for Intel Mode-Based Execute Control (MBEC) and AMD Guest Mode Execution Trap (GMET) is actively under development but has not yet been merged into the mainline Linux kernel.** The most recent patchset—a combined 24‑patch **RFC v2** by KVM maintainer Paolo Bonzini—was posted on **March 26, 2026** and remains under review and testing.

Intel MBEC, introduced with **Kaby Lake** CPUs, splits the EPT execute permission into independent **supervisor (kernel)** and **user-mode** execute bits. This enables hardware acceleration for Windows **Memory Integrity / HVCI**, avoiding the costly “software MBEC” fallback that causes excessive VM exits.

**Observed performance impact (Windows 11, 8 vCPUs):**

| Configuration | VM exits / second |
|---|---:|
| Software MBEC (no eVMCS) | ~1,200,000 |
| With Enlightened VMCS (eVMCS) | ~200,000 |
| With hardware MBEC exposed | ~50,000 |

This reflects an approximately **24× reduction** versus the baseline.

AMD’s analogous feature, **GMET**, provides similar execution control with a different permission model (no supervisor-only execute; relies on the U/S bit).

---

## 2. Relevant Subsystems and Mailing Lists

### Kernel Subsystems
- **KVM x86** (core virtualization)
- **VMX** (`arch/x86/kvm/vmx/`) – Intel virtualization

