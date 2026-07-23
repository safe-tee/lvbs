#!/bin/bash

SOURCE_FOLDER="$(realpath $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/..)"
# Honor a caller-provided LINUX_SRC_ROOT; otherwise auto-detect the kernel
# sources in the current workspace layout, falling back to the legacy path.
LINUX_SRC_ROOT="${LINUX_SRC_ROOT:-}"
if [ -z "$LINUX_SRC_ROOT" ]; then
	if [ -d $HOME/workspaces/safe-tee/linux ]; then
		LINUX_SRC_ROOT=$HOME/workspaces/safe-tee/linux
	elif [ -d $HOME/workspaces/linux ]; then
		LINUX_SRC_ROOT=$HOME/workspaces/linux
	fi
fi
LINUX_KERNEL_CONFIG=/boot/config-$(uname -r)
BUILD_ROOT=
