#!/bin/bash
#
# Out-of-tree Linux kernel build for LVBS.
#
# Kernel sources live in ~/workspaces/safe-tee/linux and all build
# artifacts are placed in <lvbs>/build/kernel so the source tree stays clean.
#
# A single kernel is built with VBS/HEKI plus the KVM VM-planes backend so the
# same image can act as both the normal (plane 0) and secure (plane 1) kernel.
# The VBS options are built-in on purpose: they participate in early boot and
# plane setup, so they cannot be loadable modules.
#
set -euo pipefail

SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LVBS_ROOT="$( cd "$SCRIPTS_DIR/.." &> /dev/null && pwd )"

# Location of the kernel sources (override with LINUX_SRC_ROOT).
LINUX_SRC_ROOT="${LINUX_SRC_ROOT:-$HOME/workspaces/safe-tee/linux}"

# Out-of-tree build output directory (override with BUILD_ROOT).
BUILD_ROOT="${BUILD_ROOT:-$LVBS_ROOT/build/kernel}"

# Base kernel config (override with LINUX_KERNEL_CONFIG). There is no in-tree
# LVBS defconfig for this kernel, so default to the running host's config and
# layer the VBS/VM-planes options on top via olddefconfig.
LINUX_KERNEL_CONFIG="${LINUX_KERNEL_CONFIG:-/boot/config-$(uname -r)}"

# VBS/HEKI core plus the KVM VM-planes backend and the in-kernel secure-plane
# monitor. All are built-in on purpose: they run during early boot / plane
# setup and cannot be loadable modules.
LVBS_CONFIG_OPTS=(VM_PLANES VBS VBS_HEKI VBS_KVM_PLANES VBS_SECURE_MONITOR)

# Subset that is mandatory: abort the build if any of these are not set after
# olddefconfig (e.g. dropped due to unmet dependencies).
LVBS_CONFIG_REQUIRED=(VM_PLANES VBS_KVM_PLANES)

enable_config() {
	local opt="$1"
	if ! grep -q "^CONFIG_${opt}=y" "$BUILD_ROOT/.config"; then
		sed -i "/^# CONFIG_${opt} is not set/d" "$BUILD_ROOT/.config"
		echo "CONFIG_${opt}=y" >> "$BUILD_ROOT/.config"
	fi
}

configure() {
	if [ ! -f "$BUILD_ROOT/.config" ]; then
		if [ ! -f "$LINUX_KERNEL_CONFIG" ]; then
			echo "Error: base config not found: $LINUX_KERNEL_CONFIG" >&2
			exit 1
		fi
		echo "Using base config: $LINUX_KERNEL_CONFIG"
		cp "$LINUX_KERNEL_CONFIG" "$BUILD_ROOT/.config"
	fi

	# Enforce the LVBS/HEKI/VSM options on every build.
	local opt
	for opt in "${LVBS_CONFIG_OPTS[@]}"; do
		enable_config "$opt"
	done

	make -C "$LINUX_SRC_ROOT" O="$BUILD_ROOT" olddefconfig

	# Fail early if a required option did not survive dependency resolution.
	local missing=()
	for opt in "${LVBS_CONFIG_REQUIRED[@]}"; do
		grep -q "^CONFIG_${opt}=y" "$BUILD_ROOT/.config" || missing+=("CONFIG_${opt}")
	done
	if [ ${#missing[@]} -ne 0 ]; then
		echo "Error: required options not enabled after olddefconfig: ${missing[*]}" >&2
		echo "Check their dependencies in the kernel Kconfig and base config." >&2
		exit 1
	fi

	echo "LVBS config enabled:"
	for opt in "${LVBS_CONFIG_OPTS[@]}"; do
		grep -E "^CONFIG_${opt}=[ym]" "$BUILD_ROOT/.config" | sed 's/^/  /'
	done
}

build() {
	configure
	make -C "$LINUX_SRC_ROOT" O="$BUILD_ROOT" -j"$(nproc)"
	make -C "$LINUX_SRC_ROOT" O="$BUILD_ROOT" -j"$(nproc)" modules
}

install() {
	sudo make -C "$LINUX_SRC_ROOT" O="$BUILD_ROOT" modules_install
	sudo make -C "$LINUX_SRC_ROOT" O="$BUILD_ROOT" install
}

clean() {
	make -C "$LINUX_SRC_ROOT" O="$BUILD_ROOT" clean
}

if [ ! -d "$LINUX_SRC_ROOT" ]; then
	echo "Error: kernel sources not found at $LINUX_SRC_ROOT" >&2
	exit 1
fi

mkdir -p "$BUILD_ROOT"

CMD="${1:-build}"
case "$CMD" in
	build)   build ;;
	install) install ;;
	clean)   clean ;;
	*)
		echo "Error: unrecognized command - $CMD" >&2
		echo "Usage: $0 [build|install|clean]" >&2
		exit 1
		;;
esac
