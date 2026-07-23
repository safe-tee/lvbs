# boot-loader

The `boot-loader` component builds the VTL1 secure-kernel boot artifacts and the
host-side CLI used to launch LVBS / KVM VM-plane guests. It is an Autotools
(autoconf/automake/libtool) project.

## Layout

| Path | Description |
| --- | --- |
| `configure.ac` | Autoconf project definition (package `lvbs`). |
| `Makefile.am` | Top-level automake file; `SUBDIRS = src`. |
| `include/` | Shared headers (`lvbs-sys.h`, generated `config.h`). |
| `src/loader/` | PVH shim loader. Wraps a raw kernel binary (`vmlinux.bin`) into a PVH-bootable ELF (`pvh_shim.elf`) for VTL1. |
| `src/cli/` | `lvbs-cli` host tool that opens `/dev/kvm`, loads the plane0/plane1 kernels, and starts the guest. |
| `build/` | Out-of-source build helper (`bootstrap.sh`). |

## Prerequisites

- `gcc`, `binutils` (`ld`, `objcopy`), `make`
- Autotools: `autoconf`, `automake`, `libtool`
- `jansson` development headers (`libjansson-dev` / `jansson-devel`)
- Linux KVM headers (`linux/kvm.h`)

## Building

The project is built out-of-source from the `build/` directory. `bootstrap.sh`
runs `autoreconf` and `configure` against the parent (component root):

```sh
cd components/boot-loader/build
./bootstrap.sh          # autoreconf -vif .. && ../configure --prefix=/usr
make
```

To configure manually (e.g. with a custom jansson prefix):

```sh
cd components/boot-loader
autoreconf -vif .
./configure --prefix=/usr [--with-jansson=<dir>]
make
```

### Artifacts

- `src/cli/lvbs-cli` — host launcher binary (installed to `$prefix/bin` via `make install`).
- `src/loader/pvh_shim.elf` — PVH-capable VTL1 shim wrapping the input kernel.

### PVH shim options

The loader wraps a raw kernel image into a PVH ELF. Override defaults on the
`make` command line:

```sh
make -C src/loader \
    INPUT_BIN=/path/to/vmlinux.bin \
    LOAD_OFFSET=0x50000000 \
    ENTRY_OFFSET=0x0
```

- `INPUT_BIN` — raw kernel payload (default `test/kernel/build-sk/vmlinux.bin`).
- `LOAD_OFFSET` — link/load address of the shim (default `0x50000000`).
- `ENTRY_OFFSET` — payload entry offset (default `0x0`).

## Running the CLI

```sh
lvbs-cli [plane0_kernel] [plane1_kernel] [plane]
```

- `plane0_kernel` — guest (plane 0) kernel image; defaults to
  `~/workspaces/lvbs/test/mkosi-kvm/fedora-kvm.vmlinuz`.
- `plane1_kernel` — secure (plane 1) kernel; defaults to the host
  `/boot/vmlinux-*` image.
- `plane` — starting plane index (default `0`).

Requires read/write access to `/dev/kvm`.

## Cleaning

```sh
make clean        # remove build outputs
```
