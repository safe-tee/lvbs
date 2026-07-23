# Secure Kernel

This is a tiny, self-contained secure kernel that runs in VM Plane 1.

```bash
./build-sk.sh
```

Artifacts are written to `build-sk/` (`bzImage`, `vmlinux`, `vmlinux.bin`). You
can also build it from the workspace root with:

```bash
make secure-kernel
```

To build the regular Plane 0 kernel with VM Planes support, use the top-level
build instead (`make kernel`, see `scripts/build-kernel.sh`).

