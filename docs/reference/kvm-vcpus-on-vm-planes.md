# Notes on vCPU mapping with VM Planes on KVM

## vCPUs

1. A Virtual CPU (vCPU) is mapped to a specific physical CPU core on the host during execution.
1. A vCPU is immutable for a given Virtual Machine being managed by KVM.
1. A vCPU has pointers to all the VM Storage Areas which contain the execution context (state) corresponding to the VM PLanes.
    1. Each VM Plane has an associated VMSA which contains the register and control state.
1. A vCPU may transition between various VM Planes. However, only one Plane context (VMSA) is active for a vCPU any time.
    1. The Plane determines which instructions the vCPU may execute.
    1. The Plane determines which memory regions it may access, governed by per-VMPL permission masks in the h/w reverse map table (RMP).

## VM Planes

1. All the VM Planes in a VM share the same Address Space Identifier (ASID).
    1. This enables the VMPLs to share the same encrypted memory domain. However, per-page permissions are different.
1. The VM can use RMPADJUST to modify the permissions of the VMPLs numerically higher (less privileged) than its own.
    1. For example, a vCPU executing at VMPL-1 cannot alter its own permissions or the permissions of VMPL-0.
    1. When the hypervisor assigns a memory page to a guest using RMPUPDATE, full permissions are enabled for VMPL-0 (privileged) and disabled for all other VMPLs. This allows the higher privileged VMPL to govern access to the lower privileged ones.
    1. When a Guest access results in a VMEXIT (NPF) due to a VMPL permission violation, an error code bit in EXITINFO1 is set.
    1. It is illegal to configure a page VMPL write permissions but not read permissions. A data access to such a page will result in VMEXIT (NPF).
1. A VM Plane Switch will cause a different VMSA to be loaded. The same vCPU will execute in the newly transitioned VM PLane.
1. A VM Plane uses the KVM_EXIT_PLANE_EVENT to alert or preempt another plane.
1. The VMPL enforcement is per-access, on any core.
    1. The processor checks the current VMPL permission mask of the page on every memory access.
    1. If the physical core supports SEV-SNP, h/w enforcement is uniform regardless of which core the thread runs on.
1. The active VMPL is encoded in the loaded VMSA.
    1. When KVM reschedules a vCPU thread on a different core, it loads the correct VMSA and h/w continues enforcement seamlessly.
1. The choice of which plane to execute is made through vcpu->run and not by scheduling separate threads.
    1. The host scheduler just schedules the thread and KVM internally determines the active plane context (VMSA).

## Hyper-V Virtual Trust Levels versus KVM VM Planes

Microsoft Hyper-V's Virtual Trust Levels are hierarchical. Hyper-V partitions physical memory between various trust levels using second level address translations (SLAT) and enforces per-VTL memory access to these memory ranges, which cannot be overridden by the supervisor.

The VTL trust boundaries encompass memory, device, virtual processor and virtual interrupt state.

In the VM Planes design proposed for KVM, one host kernel thread is mapped to a single vCPU which operates on a single plane at a time. This means a vCPU blocked waiting for a response from the secure plane cannot simultaneously make progress on the normal plane. Workloads that are dominated by cross-plane calls might suffer from latency bottlenecks.

## Use case involving the SVSM and VM Planes

When the Guest OS Workload invokes a call to the SVSM (say access to the vTPM), the same vCPU thread transitions from the lower privileged Guest Plane (VMPL-2 or Plane 0) to the secure plane (VMPL-0 or Plane 1), executes the requested service and returns.