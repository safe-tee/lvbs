# Linux Virtualization Based Security (lvbs)

## Introduction

This repository provides a workspace including tools and scripts to build and test the LVBS feature.

The LVBS feature is primarily based in the Linux Kernel and Kernel-based Virtual Machine.

## Building and running

See the [build how-to](docs/how-to/build.md) for step-by-step instructions on
cloning the sources and building every component (the Linux kernel, the optional
standalone secure kernel, QEMU, and the Fedora VM image) and launching the VM
with VM planes enabled.

A quick summary, run from the `lvbs` repository root:

```bash
make kernel          # plane 0 bzImage + plane 1 vmlinux
make qemu            # qemu-system-x86_64
make image           # fedora-kvm.raw
make secure-kernel   # optional standalone minimal plane-1 kernel (dev/debug)
```

## Assumptions

* The three source repositories are checked out side by side under a common
  workspace root, `$HOME/workspaces/safe-tee`:
  * kernel source under `$HOME/workspaces/safe-tee/linux`
  * QEMU source under `$HOME/workspaces/safe-tee/qemu`
  * lvbs source under `$HOME/workspaces/safe-tee/lvbs`
* All builds are run from the `lvbs` repository root and write their artifacts
  under `lvbs/build/`, leaving the `linux` and `qemu` source trees clean.
* The build scripts default to the layout above; override the locations with the
  `LINUX_SRC_ROOT` / `QEMU_SRC_ROOT` environment variables if your checkout
  differs (see the [build how-to](docs/how-to/build.md)).

