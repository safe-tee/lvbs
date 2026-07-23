# LVBS and HEKI Patches in CBL-Mariner-Linux-Kernel

## Code

```bash
git clone https://github.com/microsoft/CBL-Mariner-Linux-Kernel.git
cd CBL-Mariner-Linux-Kernel
git fetch --tags
git checkout tags/rolling-lts/lpg-innovate/6.6.96.1 -b lvbs
```

## Patches

Patches from the `lvbs` branch on top of the upstream AzLinux 6.6 base (~128 patches total).

---

## HEKI (Hypervisor Enforced Kernel Integrity) — Core

| # | SHA | Commit |
|---|-----|--------|
| 1 | [`d89849fd43e6`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/d89849fd43e6) | virt: Introduce Hypervisor Enforced Kernel Integrity (Heki) |
| 2 | [`a9b7cbe61a12`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/a9b7cbe61a12) | drivers: hv: Add Hyper-V support for Heki |
| 3 | [`74b2fc8770bb`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/74b2fc8770bb) | heki: Implement a kernel page table walker |
| 4 | [`74676daa382e`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/74676daa382e) | heki: x86: Initialize permissions for all guest kernel pages |
| 5 | [`f42bd327ea39`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/f42bd327ea39) | heki: x86: Remove features that need modifiable text |
| 6 | [`bcccc4118960`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/bcccc4118960) | heki: x86: Protect guest kernel memory |
| 7 | [`f2e1fb9d5d28`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/f2e1fb9d5d28) | heki: Make the VTL0 kernel immutable after boot |
| 8 | [`78d5e5d38793`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/78d5e5d38793) | heki: Add ability to skip frame protection |
| 9 | [`76436de636fd`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/76436de636fd) | heki: Fix heki_register_hypervisor declaration |
| 10 | [`8f16d2af148b`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/8f16d2af148b) | heki: Don't allocate memory for modules certificates if there are none |
| 11 | [`ccb2c7c48081`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/ccb2c7c48081) | include: linux: heki: Quick fix for all blacklist hashes not being passed to VTL1 |
| 12 | [`3d4c64cf2fc9`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/3d4c64cf2fc9) | virt: heki: module: Fix compilation error when CONFIG_SYSTEM_REVOCATION_LIST not enabled |
| 13 | [`dde207169c08`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/dde207169c08) | virt: heki: module: Send all system certificates to VTL1 |
| 14 | [`9f832f209ae0`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/9f832f209ae0) | drivers: hv: hv_common: Override heki_protect_pfn |
| 15 | [`f86c3b85fb1e`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/f86c3b85fb1e) | Enable jump label optimization with HEKI protection |
| 16 | [`687bc3b3f5a4`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/687bc3b3f5a4) | KUnit tests for HEKI |

## VSM (Virtual Secure Mode) — Boot & Infrastructure

| # | SHA | Commit |
|---|-----|--------|
| 17 | [`6d92d5c32ed3`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/6d92d5c32ed3) | Drivers: hv: Introduce basic support for Hyper-V VSM |
| 18 | [`14e07df33b36`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/14e07df33b36) | drivers: hv: Add HYPERV_VSM kconfig option |
| 19 | [`e7b3b01af7aa`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/e7b3b01af7aa) | drivers: hv: Reserve memory to load secure kernel |
| 20 | [`4ef2cf209f2d`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/4ef2cf209f2d) | firmware: efi: libstub: x86-stub: Enable VSM awareness in efi os indications variable |
| 21 | [`7c5d8e2f518b`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/7c5d8e2f518b) | drivers: hv: Enable VTL1 and boot primary cpu in VTL1 |
| 22 | [`94efb6410e87`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/94efb6410e87) | drivers: hv: Add VSM driver to run in VTL1 |
| 23 | [`c56bbe6d4a32`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/c56bbe6d4a32) | drivers: hv: mshv_vsm_vtl1: Handle VTL Parameters |
| 24 | [`d1a3b2d220a3`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/d1a3b2d220a3) | drivers: hv: hv_vsm_boot: Boot secondary processors in VTL1 |
| 25 | [`8e6e3894838e`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/8e6e3894838e) | drivers: hv: mshv_vsm_vtl1: Enable VTL1 for Secondary CPUs |
| 26 | [`e8ea11a73c38`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/e8ea11a73c38) | arch: x86: hyperv: hv_vtl: Add api to enable VTL1 for secondary cpus |
| 27 | [`3ad258d7d3ee`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/3ad258d7d3ee) | drivers: hv: mshv_vsm_vtl1: Boot secondary processors |
| 28 | [`f707c5538605`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/f707c5538605) | drivers: hv: hv_vsm_boot: Initialize VSM boot after VTL0 initcalls |
| 29 | [`4af72fc05d2c`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/4af72fc05d2c) | drivers: hv: hv_vsm_boot: Verify signatures of Secure Loader and Secure Kernel |
| 30 | [`332cace1e538`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/332cace1e538) | drivers: hv: hv_vsm_boot: Update secure kernel loading to support ELF files |
| 31 | [`901aa6392a8d`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/901aa6392a8d) | vsm: Load secure kernel directly from the running one |
| 32 | [`a2637a26278d`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/a2637a26278d) | vsm: Simplify __hv_vsm_init_vtlcall implementation |
| 33 | [`2db86604d503`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/2db86604d503) | vsm: Rework VTL call |
| 34 | [`449dfba06fd2`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/449dfba06fd2) | drivers: hv: hv_vsm_boot: Fix single CPU bootup |
| 35 | [`7fdaf17a45b6`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/7fdaf17a45b6) | drivers: hv: hv_vsm_boot: Minor fixes |
| 36 | [`f5cd3545fc43`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/f5cd3545fc43) | drivers: hv: hv_vsm_boot: Remove hv_vsm_boot_panic variable |
| 37 | [`39d17e6e8c0d`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/39d17e6e8c0d) | drivers: hv: hv_vsm_boot: Fix shared page allocation error handling |
| 38 | [`f2d79fdc6391`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/f2d79fdc6391) | drivers: hv: hv_vsm_boot: Handle errors in hv_vsm_boot_vtl1 and related functions |
| 39 | [`a9f668b6f7a4`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/a9f668b6f7a4) | drivers: hv: hv_vsm_boot: Refactor page definitions and usage |
| 40 | [`9e64a806ceb5`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/9e64a806ceb5) | drivers: hv: hv_vsm_boot: Simplify secure kernel memory reservation |
| 41 | [`3b53ae8504c3`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/3b53ae8504c3) | drivers: hv: hv_vsm_boot: Remove redundant __func__ usage |
| 42 | [`656b2e6caa4b`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/656b2e6caa4b) | drivers: hv: hv_vsm_securekernel: Fix duplicate memory reservation |
| 43 | [`b581e7da5fa6`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/b581e7da5fa6) | drivers: hv: hv_vsm_boot: Increase maximum Virtual Processors on VTL1 to 96 |
| 44 | [`b210de310fb4`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/b210de310fb4) | Allocate more memory for secure kernel by default |
| 45 | [`a7308f3f5b71`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/a7308f3f5b71) | drivers: hv_vsm_boot: Panic in case of boot failure |
| 46 | [`7f3fa76477d3`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/7f3fa76477d3) | drivers: hv: hv_vsm_boot: Pass ACPI data to secure kernel |
| 47 | [`c7c9bc807f86`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/c7c9bc807f86) | drivers: hv: mshv_vsm_vtl1: Use ACPI tables to map cpuid to apicid |
| 48 | [`8f4e66ab4928`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/8f4e66ab4928) | hyperv: Fix CONFIG_HYPERV_VSM=m |
| 49 | [`584ca7d622f7`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/584ca7d622f7) | hv: fix build break with CONFIG_MSHV_VTL without MSHV |

## VTL1 Secure Kernel — Intercepts, Registers & Memory

| # | SHA | Commit |
|---|-----|--------|
| 50 | [`e16881744391`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/e16881744391) | drivers: hv: hv_vsm_common: Add support to set and retrieve VTL0 registers from VTL1 |
| 51 | [`fe9c5d0a21eb`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/fe9c5d0a21eb) | drivers: hv: mshv_vsm_vtl1: Lock critical registers |
| 52 | [`2938c228938e`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/2938c228938e) | drivers: hv: mshv_vsm_vtl1: Introduce secure intercepts |
| 53 | [`d3e40d98ee5a`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/d3e40d98ee5a) | Introduce a common interrupt handler for vsm |
| 54 | [`38e5eb0776ae`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/38e5eb0776ae) | drivers: hv: mshv_vsm_vtl1: Handle vtl0 end of boot signal |
| 55 | [`07d826b9bc25`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/07d826b9bc25) | drivers: hv: mshv_vsm_vtl1: Api to control memory access permissions in EPT |
| 56 | [`af7fa25c4938`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/af7fa25c4938) | drivers: hv: mshv_vsm_vtl1: Add support to set EPT permissions for VTL0 memory |
| 57 | [`5d433cdcfb19`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/5d433cdcfb19) | VTL1: Avoid resetting VTL1 memory permissions when setting VTL0 memory permissions |
| 58 | [`cf0c0f1383a3`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/cf0c0f1383a3) | drivers: hv: mshv_vsm_vtl1: Fix compilation errors |
| 59 | [`a53e9eed0afb`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/a53e9eed0afb) | drivers: hv: mshv_vsm_vtl1: Fix VPs Synic initialization for the root partition |
| 60 | [`41627db51f92`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/41627db51f92) | drivers: hv: mshv_vsm_vtl1: Fix rcu stalls during secondary cpu boot |
| 61 | [`ead325b9df51`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/ead325b9df51) | drivers: hv: mshv_vsm_vtl1: Check for rcu pending before exiting VTL1 |
| 62 | [`786fdd02857e`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/786fdd02857e) | drivers: hv: vmbus: Skip VMBUS channel creation in VTL1 |

## Module Authentication (VTL0 ↔ VTL1)

| # | SHA | Commit |
|---|-----|--------|
| 63 | [`10297cda4c16`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/10297cda4c16) | Send kernel data to VTL1 |
| 64 | [`d9d08ad2f8f9`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/d9d08ad2f8f9) | Implement mapping of VTL0 memory in VTL1 |
| 65 | [`7acd17dbfae5`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/7acd17dbfae5) | Receive kernel data from VTL0 |
| 66 | [`99e8a443b853`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/99e8a443b853) | Validate VTL0 module in VTL1 |
| 67 | [`783722fcc901`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/783722fcc901) | Receive a VTL0 module and validate its contents |
| 68 | [`6b3e918abdc4`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/6b3e918abdc4) | Send kernel symbol tables to VTL1 |
| 69 | [`38c7a7815dce`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/38c7a7815dce) | Receive VTL0 kernel symbol tables and resolve VTL0 module symbols |
| 70 | [`2d04d0c94030`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/2d04d0c94030) | Validate guest module in VTL1 after relocations |
| 71 | [`d7fa4c52f795`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/d7fa4c52f795) | Pass a VTL0 module to VTL1 after post relocation fixups |
| 72 | [`aa618187e34f`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/aa618187e34f) | Apply relocations on VTL0 module contents |
| 73 | [`37cbef3341cd`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/37cbef3341cd) | Apply post relocation fixes to VTL0 module in VTL1 |
| 74 | [`405716806751`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/405716806751) | Set EPT permissions for VTL0 module sections |
| 75 | [`e6c807ac5661`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/e6c807ac5661) | Unload VTL0 module |

## Key/Certificate Management

| # | SHA | Commit |
|---|-----|--------|
| 76 | [`4c95c1502278`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/4c95c1502278) | drivers: hv: hv_vsm: Runtime Secondary Key Support Added |
| 77 | [`8ed9fec13bb6`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/8ed9fec13bb6) | drivers: hv: mshv_vsm_vtl1: Support to add runtime secondary key in secure kernel |
| 78 | [`b6a6fb49794d`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/b6a6fb49794d) | Add Support for Sending Blacklist/Revocation Keyring Data to Secure Kernel |
| 79 | [`61cf9afeb2e9`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/61cf9afeb2e9) | drivers: vsm: mshv_vsm_vtl1: Add Support for Receiving Blacklist/Revocation Keyring Data from Guest Kernel |

## Kexec Support (VTL0 ↔ VTL1)

| # | SHA | Commit |
|---|-----|--------|
| 80 | [`756c7c88eb29`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/756c7c88eb29) | VTL0: Code reorganization required for kexec support |
| 81 | [`876bf2b221a4`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/876bf2b221a4) | VTL1: Code reorganization required for kexec support |
| 82 | [`3fcefb30a019`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/3fcefb30a019) | VTL0: Place the kimage structure in a separate page |
| 83 | [`9711dc544e4b`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/9711dc544e4b) | VTL0: Implement the Kexec Validate VTL call |
| 84 | [`518556172c61`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/518556172c61) | VTL1: Implement the Kexec Validate VTL call |
| 85 | [`b93a35e933cb`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/b93a35e933cb) | VTL0: Send the kernel blob to VTL1 for signature verification |
| 86 | [`243502f8f35a`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/243502f8f35a) | VTL1: Receive the kernel blob from VTL0 and verify its signature |
| 87 | [`0cd7674d76a9`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/0cd7674d76a9) | VTL0: Send all of the kexec data to VTL1 |
| 88 | [`afaa36a9ec1e`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/afaa36a9ec1e) | VTL1: Receive all of the kexec data in VTL1 |
| 89 | [`82550798fd23`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/82550798fd23) | VTL0: Implement the kexec invalidate call in VTL0 |
| 90 | [`fedd8e5b5857`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/fedd8e5b5857) | VTL1: Implement the kexec invalidate call in VTL1 |
| 91 | [`0dd73336814f`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/0dd73336814f) | VTL0: Allow the kexec_load syscall to unload kexec kernel images |
| 92 | [`b94aba1080fd`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/b94aba1080fd) | VTL0: Include control pages for crash kexec in kexec_file_load |
| 93 | [`b11c44cb8a05`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/b11c44cb8a05) | VTL1: Map kexec kernel image struct into VTL1 address space |
| 94 | [`6ce8d2878553`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/6ce8d2878553) | VTL1: Protect kexec segments when a kexec kernel is loaded |
| 95 | [`788467931564`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/788467931564) | VTL1: Make the kexec trampoline non-executable |
| 96 | [`ba92aaf1263c`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/ba92aaf1263c) | VTL0: Make the kexec trampoline non-executable |

## x86/Hyper-V VTL Plumbing

| # | SHA | Commit |
|---|-----|--------|
| 97 | [`40658392f4de`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/40658392f4de) | x86: hyperv: hv_vtl: Split the logic enabling higher VTL for secondary cpus |
| 98 | [`dfa30251b4c3`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/dfa30251b4c3) | x86: hyperv: Add vtl awareness to hv_vtl_early_init |
| 99 | [`91c10db86b0d`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/91c10db86b0d) | arch: x86: hyperv: hv_vtl: Fix for APIC issue with 6.6 kernel |
| 100 | [`663231e547ca`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/663231e547ca) | x86: idle: Allows mshv_vtl to change the idle routine |

## Retpoline / Return Thunk / Text Patching

| # | SHA | Commit |
|---|-----|--------|
| 101 | [`25770d06ad50`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/25770d06ad50) | vtl0: Enable Return Thunk support |
| 102 | [`60d456c3103a`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/60d456c3103a) | vtl1: Enable Return Thunk support for vtl0 modules |
| 103 | [`d5f4f56d79f4`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/d5f4f56d79f4) | Fix retpoline and return thunk info passing from VTL0 to VTL1 |
| 104 | [`6815031a95a5`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/6815031a95a5) | Fix handling of retpoline and return thunk addresses during text patching |

## Config / Build / Infrastructure

| # | SHA | Commit |
|---|-----|--------|
| 105 | [`d6519f90e83e`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/d6519f90e83e) | Microsoft: Add config fragment to build lvbs enabled kernel |
| 106 | [`a3483af30226`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/a3483af30226) | Microsoft: Add lvbs-build script |
| 107 | [`04b7146335b4`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/04b7146335b4) | Microsoft: lvbs-build: Add support to specify kernel version |
| 108 | [`4ec2eca733b1`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/4ec2eca733b1) | Microsoft: lvbs.conf: Disable config options to ensure struct module has same size |
| 109 | [`afdd05f16d04`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/afdd05f16d04) | lvbs.config: Add CONFIG_MODULE_SIG dependency |
| 110 | [`a91db5d3d8f6`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/a91db5d3d8f6) | lvbs.config: Add CONFIG_HYPERV dependency |
| 111 | [`5200cf7ef4ba`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/5200cf7ef4ba) | Add config for secure kernel |
| 112 | [`5cd4a9b7d9b1`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/5cd4a9b7d9b1) | Add initrd for secure kernel |
| 113 | [`e0a9152642ea`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/e0a9152642ea) | Add sk-loader.bin and vmlinux.bin to VTL0 initramfs |
| 114 | [`a105754cf216`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/a105754cf216) | VTL0: Enable CONFIG_RETPOLINE |
| 115 | [`f0709959a937`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/f0709959a937) | VTL1: Enable CONFIG_RETPOLINE |
| 116 | [`d24c41cf2b11`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/d24c41cf2b11) | arch: x86: Kconfig: Enable IBT on VTL0 |
| 117 | [`3bcaafa957de`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/3bcaafa957de) | VTL0: Fix config for pv_ops |
| 118 | [`2e6ec87553c9`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/2e6ec87553c9) | VTL1: Fix config for pv_ops |
| 119 | [`191f64494d8c`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/191f64494d8c) | Revert "VTL1: Fix config for pv_ops" |
| 120 | [`922af15dc9d3`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/922af15dc9d3) | VTL0: Fix config for kexec |
| 121 | [`1fc6098bff26`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/1fc6098bff26) | Microsoft: Disable MITIGATION_ITS |
| 122 | [`c170f518926f`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/c170f518926f) | Microsoft: add_sk_to_initramfs.sh: Clean up script |
| 123 | [`9d10297b0b54`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/9d10297b0b54) | Microsoft: azl3_secure_config: Enable RETHUNK |
| 124 | [`d041f89c7e2c`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/d041f89c7e2c) | Microsoft: azl3_secure_config: Remove unused features |

## Misc Fixes

| # | SHA | Commit |
|---|-----|--------|
| 125 | [`5a6d4257c7cf`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/5a6d4257c7cf) | Allow LVBS to boot on an Azlinux VM in Azure |
| 126 | [`4cf8d0357493`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/4cf8d0357493) | VTL0: Fix a typo |
| 127 | [`3c25e53f29cd`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/3c25e53f29cd) | VTL0: Revert changes to kernel/kexec.c |
| 128 | [`70fc7f1e1fda`](https://github.com/microsoft/CBL-Mariner-Linux-Kernel/commit/70fc7f1e1fda) | VTL0: Revert the hyperv_cleanup() reorg |

---

## Summary

| Category | Count |
|----------|-------|
| HEKI Core | 16 |
| VSM Boot & Infrastructure | 33 |
| VTL1 Intercepts, Registers & Memory | 13 |
| Module Authentication (VTL0 ↔ VTL1) | 13 |
| Key/Certificate Management | 4 |
| Kexec Support (VTL0 ↔ VTL1) | 17 |
| x86/Hyper-V VTL Plumbing | 4 |
| Retpoline / Return Thunk / Text Patching | 4 |
| Config / Build / Infrastructure | 20 |
| Misc Fixes | 4 |
| **Total** | **128** |
