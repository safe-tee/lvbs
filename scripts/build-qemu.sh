#!/bin/bash
#
# Out-of-tree QEMU build for LVBS.
#
# QEMU sources live in ~/workspaces/qemu and all build artifacts are placed
# under <lvbs>/build/qemu so the QEMU source tree stays clean. QEMU is built
# out-of-tree in build/qemu/build (its meson/ninja build directory), and the
# resulting system emulator(s) and tools are staged directly in build/qemu.
#
# By default only the x86_64 system emulator is built (qemu-system-x86_64),
# which is what LVBS boot testing needs. Override the target list with
# QEMU_TARGETS (e.g. "x86_64-softmmu,aarch64-softmmu").
#
# Build prerequisites (Fedora): python3, ninja-build, meson, glib2-devel,
# pixman-devel, and the usual C toolchain. configure will report any missing
# dependency.
#
set -euo pipefail

SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LVBS_ROOT="$( cd "$SCRIPTS_DIR/.." &> /dev/null && pwd )"

# Location of the QEMU sources (override with QEMU_SRC_ROOT).
QEMU_SRC_ROOT="${QEMU_SRC_ROOT:-$HOME/workspaces/safe-tee/qemu}"

# Out-of-tree staging directory (override with BUILD_ROOT).
BUILD_ROOT="${BUILD_ROOT:-$LVBS_ROOT/build/qemu}"

# Meson/ninja build directory, kept under the staging dir.
BUILD_DIR="$BUILD_ROOT/build"

# System emulator targets to build (override with QEMU_TARGETS).
QEMU_TARGETS="${QEMU_TARGETS:-x86_64-softmmu}"

# Extra flags passed verbatim to QEMU's configure (override with
# QEMU_CONFIGURE_EXTRA).
QEMU_CONFIGURE_EXTRA="${QEMU_CONFIGURE_EXTRA:-}"

configure() {
	# QEMU detects an out-of-tree build from the invoking directory; run its
	# configure from BUILD_DIR with an absolute path to the source tree.
	if [ ! -f "$BUILD_DIR/build.ninja" ]; then
		mkdir -p "$BUILD_DIR"
		echo "Configuring QEMU (targets: $QEMU_TARGETS)"
		# shellcheck disable=SC2086
		( cd "$BUILD_DIR" && "$QEMU_SRC_ROOT/configure" \
			--target-list="$QEMU_TARGETS" \
			$QEMU_CONFIGURE_EXTRA )
	fi
}

build() {
	configure
	# QEMU generates a GNU Make wrapper in the build dir that drives ninja.
	make -C "$BUILD_DIR" -j"$(nproc)"
	stage
}

stage() {
	echo "Staging QEMU artifacts in $BUILD_ROOT:"
	local staged=0 f
	shopt -s nullglob
	for f in "$BUILD_DIR"/qemu-system-* "$BUILD_DIR"/qemu-img "$BUILD_DIR"/qemu-nbd; do
		# Skip meson's per-target object directories (e.g. qemu-system-x86_64.p).
		[ -f "$f" ] || continue
		install -m 0755 "$f" "$BUILD_ROOT/"
		echo "  $(basename "$f")"
		staged=1
	done
	shopt -u nullglob
	if [ "$staged" -eq 0 ]; then
		echo "Error: no QEMU binaries found to stage in $BUILD_DIR" >&2
		exit 1
	fi
}

clean() {
	# Remove the out-of-tree build directory and any staged binaries.
	rm -rf "$BUILD_DIR"
	shopt -s nullglob
	rm -f "$BUILD_ROOT"/qemu-system-* "$BUILD_ROOT"/qemu-img "$BUILD_ROOT"/qemu-nbd
	shopt -u nullglob
	echo "Cleaned QEMU build output under $BUILD_ROOT"
}

install_qemu() {
	# Ensure QEMU is configured and built, then install to the configured
	# prefix (default /usr/local). Building runs as the current user; only the
	# install step needs elevated privileges for a system prefix.
	build
	local sudo=""
	if [ "$(id -u)" -ne 0 ]; then
		sudo="sudo"
	fi
	echo "Installing QEMU to the configured prefix (uses sudo)..."
	$sudo make -C "$BUILD_DIR" install
}

if [ ! -x "$QEMU_SRC_ROOT/configure" ]; then
	echo "Error: QEMU sources not found at $QEMU_SRC_ROOT" >&2
	echo "Set QEMU_SRC_ROOT to your QEMU checkout." >&2
	exit 1
fi

mkdir -p "$BUILD_ROOT"

CMD="${1:-build}"
case "$CMD" in
	build)   build ;;
	install) install_qemu ;;
	clean)   clean ;;
	*)
		echo "Error: unrecognized command - $CMD" >&2
		echo "Usage: $0 [build|install|clean]" >&2
		exit 1
		;;
esac
