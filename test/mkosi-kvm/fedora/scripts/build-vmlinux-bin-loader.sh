#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT_BIN="${1:-$SCRIPT_DIR/../../kernel/build-sk/vmlinux.bin}"
LOAD_OFFSET="${3:-0x50000000}"
MAKE_DIR="${MAKE_DIR:-$SCRIPT_DIR/../../../build/src/loader}"
OUTPUT_ELF="${2:-$MAKE_DIR/lvbs-vtl1-pvh-shim.elf}"
INPUT_ELF_DEFAULT="${INPUT_BIN%.bin}"
INPUT_ELF="${INPUT_ELF:-$INPUT_ELF_DEFAULT}"
ENTRY_OFFSET="${ENTRY_OFFSET:-0x0}"

if ! command -v make >/dev/null 2>&1; then
	echo "Required tool 'make' not found in PATH." >&2
	exit 1
fi

if [[ ! -f "$INPUT_BIN" ]]; then
	echo "Input kernel binary not found: $INPUT_BIN" >&2
	exit 1
fi

if file -b "$INPUT_BIN" | grep -q '^ELF '; then
	echo "Input appears to be an ELF image: $INPUT_BIN" >&2
	echo "Pass the raw build-sk payload (vmlinux.bin), not vmlinux." >&2
	exit 1
fi

if [[ -f "$INPUT_ELF" ]] && file -b "$INPUT_ELF" | grep -q '^ELF '; then
	# Compute the payload entry offset. Prefer PVH symbol entry when present.
	ENTRY_OFFSET="$(python3 - "$INPUT_ELF" <<'PY'
import re
import subprocess
import sys

path = sys.argv[1]
hdr = subprocess.check_output(["readelf", "-h", path], text=True)
ph = subprocess.check_output(["readelf", "-lW", path], text=True)
symtab = subprocess.check_output(["readelf", "-sW", path], text=True)

m = re.search(r"Entry point address:\s*(0x[0-9a-fA-F]+)", hdr)
if not m:
	raise SystemExit("failed to parse ELF entry")
entry = int(m.group(1), 16)

lowest_p = None
lowest_v = None
for line in ph.splitlines():
	s = line.strip()
	if not s.startswith("LOAD"):
		continue
	cols = s.split()
	if len(cols) < 4:
		continue
	vaddr = int(cols[2], 16)
	paddr = int(cols[3], 16)
	lowest_v = vaddr if lowest_v is None else min(lowest_v, vaddr)
	lowest_p = paddr if lowest_p is None else min(lowest_p, paddr)

if lowest_p is None or lowest_v is None:
	raise SystemExit("no PT_LOAD entries in ELF")

def parse_symbol_addr(name: str):
	for line in symtab.splitlines():
		if not line.strip().endswith(name):
			continue
		cols = line.split()
		if len(cols) < 8:
			continue
		try:
			return int(cols[1], 16)
		except ValueError:
			continue
	return None

def to_payload_offset(addr: int):
	# vmlinux symbols are usually virtual. If so, convert to payload offset via VMA base.
	if addr >= lowest_v:
		return addr - lowest_v
	# Some symbols (e.g. phys_startup_64) are absolute physical.
	if addr >= lowest_p:
		return addr - lowest_p
	return None

chosen_addr = None
for sym in ("pvh_start_xen", "phys_startup_64"):
	a = parse_symbol_addr(sym)
	if a is not None:
		chosen_addr = a
		break

if chosen_addr is None:
	chosen_addr = entry

offset = to_payload_offset(chosen_addr)
if offset is None or offset < 0:
	raise SystemExit("computed invalid payload entry offset")

print(hex(offset))
PY
	)"
fi

exec make -C "$MAKE_DIR" pvh-shim-elf \
	INPUT_BIN="$INPUT_BIN" \
	ENTRY_OFFSET="$ENTRY_OFFSET" \
	OUTPUT_ELF="$OUTPUT_ELF" \
	LOAD_OFFSET="$LOAD_OFFSET"
