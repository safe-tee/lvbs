# How to build and run the LVBS system

This guide walks through cloning the sources and building every component of the
Linux Virtualization Based Security (LVBS) workspace: the Linux kernel (which
serves as both the normal *plane 0* and the secure *plane 1*), QEMU, and the
Fedora-based VM image. It finishes by launching the VM with VM planes enabled.

## Overview

LVBS is composed of three source repositories that live side by side under a
common workspace root:

| Repository | Purpose | Default branch |
|------------|---------|----------------|
| `linux` | Kernel with VBS/HEKI plus the KVM VM-planes backend | `vm-planes-merged` |
| `qemu`  | QEMU with VM-planes support (x86_64 system emulator) | `vm-planes-merged` |
| `lvbs`  | This repo: build scripts, image definition, tests | `vm-planes-merged` |

The `lvbs` repository is the orchestrator. Its top-level `Makefile` and the
scripts under `scripts/` drive out-of-tree builds of the kernel and QEMU and
compose the VM image with `mkosi`. All build artifacts are written under
`lvbs/build/` so the `linux` and `qemu` source trees stay clean.

A **single kernel** is built with `CONFIG_VM_PLANES`, `CONFIG_VBS`,
`CONFIG_VBS_HEKI`, `CONFIG_VBS_KVM_PLANES`, and `CONFIG_VBS_SECURE_MONITOR`. The
same kernel image serves both planes: plane 0 boots the compressed `bzImage`
and plane 1 runs the uncompressed `vmlinux` ELF.

For development and debugging there is also an optional **standalone secure
kernel** (`make secure-kernel`) — a tiny, self-contained plane-1 kernel with an
embedded initramfs. It is not needed for the default image build (which reuses
the single kernel above for plane 1) but is useful for isolating plane-1
behaviour. See [section 3](#3-build-the-standalone-secure-kernel-optional).

## Prerequisites

The build is developed and tested on Fedora. Install the toolchains and
dependencies for the kernel, QEMU, and image build:

```bash
# Kernel + general build toolchain
sudo dnf install -y gcc make flex bison elfutils-libelf-devel openssl-devel \
    bc perl dwarves ncurses-devel

# QEMU build dependencies
sudo dnf install -y python3 ninja-build meson glib2-devel pixman-devel \
    zlib-devel

# Image build (mkosi) + firmware + tooling
sudo dnf install -y mkosi systemd-ukify dracut edk2-ovmf qemu-img
```

You also need:

- A host CPU with hardware virtualization (Intel VT-x / AMD-V) and access to
  `/dev/kvm`.
- `git` with SSH access configured for `github.com:safe-tee/*` (the clone URLs
  below use SSH).

> QEMU's `configure` step reports any missing dependency, so start the QEMU
> build early if you are unsure whether all packages are installed.

## 1. Clone the sources

By convention the three repositories are checked out side by side under
`$HOME/workspaces/safe-tee`. The build scripts default to this layout (override
with the environment variables noted later if you use a different path).

```bash
mkdir -p ~/workspaces/safe-tee
cd ~/workspaces/safe-tee

git clone git@github.com:safe-tee/linux.git
git clone git@github.com:safe-tee/qemu.git
git clone git@github.com:safe-tee/lvbs.git

# Check out the working branch in each repo
for d in linux qemu lvbs; do
    git -C "$d" checkout vm-planes-merged
done
```

After cloning, the layout should look like:

```
~/workspaces/safe-tee/
├── linux/    # kernel sources
├── qemu/     # QEMU sources
└── lvbs/     # build scripts, image, tests (run builds from here)
```

All remaining commands are run from the `lvbs` directory:

```bash
cd ~/workspaces/safe-tee/lvbs
```

## 2. Build the kernel (plane 0 + plane 1)

The kernel is built out-of-tree into `build/kernel`. The build script starts
from the running host's config (`/boot/config-$(uname -r)`), then layers the
LVBS options on top via `olddefconfig` and fails early if a required option
(`CONFIG_VM_PLANES`, `CONFIG_VBS_KVM_PLANES`) did not survive dependency
resolution.

```bash
make kernel
```

This produces both artifacts from one build:

- `build/kernel/arch/x86/boot/bzImage` — compressed image for **plane 0**.
- `build/kernel/vmlinux` — uncompressed ELF for **plane 1**.

The build is incremental: rerun `make kernel` after editing kernel sources to
recompile only what changed.

### Useful overrides

The kernel build script (`scripts/build-kernel.sh`) accepts these environment
variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `LINUX_SRC_ROOT` | `~/workspaces/safe-tee/linux` | Kernel source tree |
| `BUILD_ROOT` | `lvbs/build/kernel` | Out-of-tree build output |
| `LINUX_KERNEL_CONFIG` | `/boot/config-$(uname -r)` | Base config to start from |

### Installing modules on the host (optional)

If you want the freshly built `kvm` / `kvm_intel` modules on the *host* (for
example when you also modified host-side KVM code), install them:

```bash
make kernel-install    # runs modules_install + install with sudo
```

After installing changed KVM modules you must reload them for the change to take
effect (QEMU must be stopped first because it holds `/dev/kvm`):

```bash
sudo pkill qemu || true
sudo rmmod kvm_intel kvm
sudo modprobe kvm_intel
```

> Tip: verify the running module matches your build by comparing build IDs:
> `file "$(modinfo -n kvm)"` vs `file build/kernel/arch/x86/kvm/kvm.ko`.

## 3. Build the standalone secure kernel (optional)

The default image reuses the single VM-planes kernel from section 2 for plane 1,
so this step is **not required** for a normal build/run. The standalone secure
kernel is a separate, minimal plane-1 kernel that is handy when you want to
develop or debug plane-1 behaviour in isolation.

It is built by `components/secure-kernel/build-sk.sh` and differs from the main
kernel in that it:

- Starts from `x86_64_defconfig` (not the host config) and strips out drivers
  and subsystems the secure plane does not need (DRM, sound, USB, HID, PCI,
  block/SCSI/NVMe, most filesystems, etc.).
- Embeds a minimal statically linked initramfs (`components/secure-kernel/initramfs-sk/`)
  so it can boot and park without an external rootfs.
- Enables only the plane-1 handshake support — `CONFIG_VBS_SECURE_MONITOR=y`
  (activated by the `secure_monitor` kernel command-line option) — without the
  full VBS/HEKI stack.
- Pins `CONFIG_PHYSICAL_START`/`CONFIG_PHYSICAL_ALIGN` to `0x1000000` to match
  the plane's load offset.

```bash
make secure-kernel
```

Artifacts are written under `components/secure-kernel/build-sk/`:

- `bzImage` — compressed image.
- `vmlinux` — uncompressed ELF.
- `vmlinux.bin` — raw binary (`.note`/`.comment` stripped), the form a
  direct-boot loader consumes for plane 1.

The build is incremental. To rebuild from scratch, remove the output directory:

```bash
rm -rf components/secure-kernel/build-sk
```

> The secure kernel build reuses the shared `linux` source tree. Override the
> source location with `LINUX_SRC_ROOT` if your checkout is not at
> `~/workspaces/safe-tee/linux`.

## 4. Build QEMU

QEMU is built out-of-tree; the meson/ninja build directory lives under
`build/qemu/build` and the resulting emulator binary is staged in `build/qemu`.
By default only the x86_64 system emulator (`qemu-system-x86_64`) is built,
which is all LVBS boot testing needs.

```bash
make qemu
```

The staged binary is `build/qemu/qemu-system-x86_64`.

### Useful overrides

| Variable | Default | Purpose |
|----------|---------|---------|
| `QEMU_SRC_ROOT` | `~/workspaces/safe-tee/qemu` | QEMU source tree |
| `BUILD_ROOT` | `lvbs/build/qemu` | Staging directory |
| `QEMU_TARGETS` | `x86_64-softmmu` | Target list, e.g. `x86_64-softmmu,aarch64-softmmu` |
| `QEMU_CONFIGURE_EXTRA` | *(empty)* | Extra flags passed verbatim to `configure` |

To install QEMU system-wide to the configured prefix (default `/usr/local`,
uses `sudo` for the install step only):

```bash
make qemu-install
```

To run the launch script (next section) without a system install, put the
staged binary on your `PATH` for the current shell:

```bash
export PATH="$PWD/build/qemu:$PATH"
```

## 5. Build the Fedora VM image

The VM image is composed with `mkosi` from `image/fedora`. The build script
(`scripts/build-image.sh`) stages both plane kernels and generates the VM-planes
configuration before invoking `mkosi`:

- Copies the plane-1 `vmlinux` into the image at `boot/plane-1/vmlinux`.
- Installs (and prunes to KVM-essential) kernel modules for the initrd.
- Generates `config-vm-planes` (consumed by `linux/init/vm_planes.c`) describing
  the plane count, the carved plane-1 RAM region, and the plane-1 kernel command
  line.
- Builds a Fedora 43 disk image with a UKI (Unified Kernel Image) and
  systemd-boot.

Because the `image` target depends on the kernel *artifacts*, it will not
rebuild the kernel if `bzImage` and `vmlinux` already exist:

```bash
make image
```

To force a fresh kernel first, then rebuild the image:

```bash
make kernel image
```

The primary output is the disk image `image/fedora/fedora-kvm.raw`.

> The default image uses the plane-1 `vmlinux` from the single kernel built in
> section 2. The standalone secure kernel from
> [section 3](#3-build-the-standalone-secure-kernel-optional) is independent of
> this image build and is only used for isolated plane-1 experiments.

### Plane-1 memory carve-out

The plane-1 (secure) kernel runs from RAM carved out of plane 0. The defaults in
`scripts/build-image.sh` place it at `[0x40000000, 0x7c000000)` (a 960 MB region
starting at 1 GB) and add a matching `memmap=` reservation to the plane-0
command line so plane 0 never allocates there. These are overridable via
`VTL1_LOAD_OFFSET` and `VTL1_MEMORY_SIZE`, but the defaults are chosen to satisfy
several constraints (stay below 4 GB, clear the low real-mode trampoline, and end
below the firmware ACPI tables). Change them only if you understand those
constraints.

## 6. Run the VM with planes enabled

Launch the VM with the helper script. It boots the Fedora disk image under
OVMF/UEFI secure boot with VM planes enabled (split irqchip, which VM planes
require):

```bash
./test/qemu/create-vm.sh
```

By default this:

- Uses `image/fedora/fedora-kvm.raw` as the plane-0 disk.
- Allocates 4 GB RAM and 3 vCPUs.
- Puts plane 0's console on stdio, and redirects the plane-1 secure kernel's
  serial output (COM2) to `/tmp/plane1-serial.log` so the two do not interleave.

Common overrides (flags or environment variables):

```bash
./test/qemu/create-vm.sh --memory 8G --smp 4
ENABLE_PLANES=0 ./test/qemu/create-vm.sh        # boot plane 0 only
PLANE0_DISK=/path/to/other.raw ./test/qemu/create-vm.sh
```

`qemu-system-x86_64` must be resolvable on `PATH` — either from `make
qemu-install` or by prepending `build/qemu` as shown in section 3.

### What a successful boot looks like

- Plane 0 boots Fedora to a login prompt (default credentials: user `root`,
  password `mkosi`).
- `/tmp/plane1-serial.log` shows the secure plane starting and parking, e.g.
  `vbs-secmon: secure monitor started` and `vbs-secmon: protected RAM ...`.
- Plane 0's console reports the VBS backend registering and the kernel being
  sealed, e.g. `vbs: registered backend kvm-planes` and
  `vbs: HEKI: kernel sealed successfully`.

## Cleaning up

Each component has a clean target:

```bash
make kernel-clean    # clean the kernel build
make qemu-clean      # remove the QEMU build dir and staged binaries
make image-clean     # remove mkosi outputs and generated staging content
```

The standalone secure kernel has no clean target; remove its output directory
directly:

```bash
rm -rf components/secure-kernel/build-sk
```

## Quick reference

```bash
# One-time: clone
mkdir -p ~/workspaces/safe-tee && cd ~/workspaces/safe-tee
git clone git@github.com:safe-tee/linux.git
git clone git@github.com:safe-tee/qemu.git
git clone git@github.com:safe-tee/lvbs.git
for d in linux qemu lvbs; do git -C "$d" checkout vm-planes-merged; done

# Build everything from the lvbs repo
cd ~/workspaces/safe-tee/lvbs
make kernel          # plane 0 bzImage + plane 1 vmlinux
make qemu            # qemu-system-x86_64
make image           # fedora-kvm.raw

# Optional: standalone minimal plane-1 kernel (dev/debug only)
make secure-kernel   # components/secure-kernel/build-sk/{bzImage,vmlinux,vmlinux.bin}

# Run
export PATH="$PWD/build/qemu:$PATH"
./test/qemu/create-vm.sh
```
