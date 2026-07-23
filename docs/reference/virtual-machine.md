# Some notes on Virtualization

A Hypervisor (Virtual Machine Monitor) runs at a higher CPU privilege level for the entire lifetime of the system.
At this privilege level, the monitor (VMM) has direct oversight of the OS running in the VM below.

The Kernel-based Virtual Machine (KVM) uses the Linux Kernel as the monitor with each VM as a process on the host.
Hardware assistance is provided through VT-d, AMD-V, EL2 etc. to help provide full virtualization.

The Hypervisor uses an extra layer of memory isolation, to ensure the guest can only access its own memory.

* On Intel, Extended Page Tables (EPT)
* On AMD, Nested Page Tables (NPT)
* On Arm, Stage-2 Page Tables

On Hyper-V, this is achieved by Virtual Secure Mode (VSM) where the physical memory is partitioned into Secondary Level Address Translation (SLAT).
Each Virtual Trust Level (VTL) is then made to access only the memory regions assigned and which cannot be overridden by the supervisor.
Under Hypervisor-Based Code Integrity (HVCI), using SLAT, host memory is not executable by default; pages must pass integrity verification before being marked executable.

On KVM, the hypervisor's Extended or Stage-2 Page Tables are not accessible by the Guest VM.

When the Guest Kernel performs a restricted operation (HLT, control register write, MSR access etc.), the CPU performs a VM Exit, giving control to the Hypervisor. The Hypervisor can optionally block or log the operation before resuming (giving control back) to the guest.

Hardware supported Mode Based Execution Control (MBEC) splits the EPT execute permission bit into two independent bits; one for supervisor mode (kernel) execution and one for user-mode execution. Therefore, the Hypervisor can distinguish the corresponding context of the VM Exit.

## x86

* The higher privilege level is VMX root mode (Ring-1).

## Arm

* The higher privilege level is EL2 (Exception Level).
* Ensure Virtualization Host Extensions - VHE (ARMv8.1+) is supported for KVM performance.
    * Without VHE, the host runs in EL1 with a KVM stub at EL2 which is not performant.
    * With VHE, the host runs at EL2 with improved performance.
* The guest kernel runs at EL1

## TrustZone

The Arm TrustZone-capable processors start executing in secure state on power-on. This means all software runs in secure mode unless the boot loader changes anything. 

Typically, a small trusted o/s (OP-TEE) runs in the secure mode whereas the rest of the O/S runs in normal mode.

OP-TEE is used for key management but not as a security monitor i.e. to implement HVCI.

