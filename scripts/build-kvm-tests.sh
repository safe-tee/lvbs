#!/bin/bash
#
# Out-of-tree build/run of the in-kernel KVM selftests for LVBS.
#
# The selftests live in the kernel sources under
# tools/testing/selftests/kvm and are built out-of-tree so the source tree
# stays clean.
#
# The tests need the kernel's generated/uapi headers, so the build reuses the
# already-built plane-0 kernel output in build/kernel as the objtree (O=).
# kselftest places the built binaries under build/kernel/kselftest/kvm.
#
# The full suite is run from the kselftest `install` tree
# (build/kernel/kselftest/kselftest_install) rather than in place: install
# co-locates the shell-wrapper tests (TEST_PROGS, e.g. nx_huge_pages_test.sh)
# with their compiled sibling binaries, which is the only layout where those
# wrappers can find their binary in a split O= build. It also emits
# run_kselftest.sh, the same runner upstream CI uses.
#
set -euo pipefail

SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LVBS_ROOT="$( cd "$SCRIPTS_DIR/.." &> /dev/null && pwd )"

# Location of the kernel sources (override with LINUX_SRC_ROOT).
LINUX_SRC_ROOT="${LINUX_SRC_ROOT:-$HOME/workspaces/safe-tee/linux}"

# Kernel build output that provides generated/uapi headers (override with
# KERNEL_BUILD_ROOT). Produced by scripts/build-kernel.sh.
KERNEL_BUILD_ROOT="${KERNEL_BUILD_ROOT:-$LVBS_ROOT/build/kernel}"

# kselftest places built binaries under <objtree>/kselftest/<target>. We reuse
# the plane-0 kernel build above as the objtree, so the KVM test binaries land
# in $KERNEL_BUILD_ROOT/kselftest/kvm.
SELFTESTS_OUTPUT="$KERNEL_BUILD_ROOT/kselftest"

# `make install` stages scripts + binaries together here and emits
# run_kselftest.sh + kselftest-list.txt. This is the default KSFT_INSTALL_PATH
# ($(BUILD)/kselftest_install) for our objtree, so we don't override it.
SELFTESTS_INSTALL="$SELFTESTS_OUTPUT/kselftest_install"

# kselftest target to build/run. Only the KVM tests by default.
TARGETS="${TARGETS:-kvm}"

# The kselftests are driven through the top-level selftests Makefile so the
# shared kselftest harness (run_tests, per-test result reporting) is available.
SELFTESTS_DIR="$LINUX_SRC_ROOT/tools/testing/selftests"

selftests_make() {
	make -C "$SELFTESTS_DIR" \
		TARGETS="$TARGETS" \
		O="$KERNEL_BUILD_ROOT" \
		"$@"
}

build() {
	if [ ! -f "$KERNEL_BUILD_ROOT/.config" ]; then
		echo "Error: kernel build output not found at $KERNEL_BUILD_ROOT" >&2
		echo "Build the kernel first: make kernel" >&2
		exit 1
	fi
	selftests_make -j"$(nproc)"
}

# Build and stage the tests into the install tree (scripts + binaries together).
install_tests() {
	if [ ! -f "$KERNEL_BUILD_ROOT/.config" ]; then
		echo "Error: kernel build output not found at $KERNEL_BUILD_ROOT" >&2
		echo "Build the kernel first: make kernel" >&2
		exit 1
	fi
	selftests_make -j"$(nproc)" install
}

# Run the full suite from the install tree via the upstream run_kselftest.sh.
# The KVM tests need a KVM-capable host (/dev/kvm). A few tests escalate with
# sudo internally (e.g. nx_huge_pages_test.sh); the harness pipes their output,
# which breaks an interactive password prompt, so cache credentials up front.
run() {
	if [ ! -x "$SELFTESTS_INSTALL/run_kselftest.sh" ]; then
		install_tests
	fi
	if [ ! -e /dev/kvm ]; then
		echo "Warning: /dev/kvm not found; the KVM selftests require a KVM-capable host." >&2
	fi
	if ! sudo -v 2>/dev/null; then
		echo "Warning: could not cache sudo credentials; tests needing root will be skipped." >&2
	fi
	( cd "$SELFTESTS_INSTALL" && ./run_kselftest.sh )
}

clean() {
	selftests_make clean
}

if [ ! -d "$LINUX_SRC_ROOT" ]; then
	echo "Error: kernel sources not found at $LINUX_SRC_ROOT" >&2
	exit 1
fi

CMD="${1:-build}"
case "$CMD" in
	build)   build ;;
	install) install_tests ;;
	run)     run ;;
	clean)   clean ;;
	*)
		echo "Error: unrecognized command - $CMD" >&2
		echo "Usage: $0 [build|install|run|clean]" >&2
		exit 1
		;;
esac
