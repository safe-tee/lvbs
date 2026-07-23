EXTRA_DIST = \
	pvh_shim.c

INPUT_BIN ?= $(top_srcdir)/test/kernel/build-sk/vmlinux.bin
BUILD_DIR = $(CURDIR)
OUTPUT_ELF ?= $(BUILD_DIR)/pvh_shim.elf
LOAD_OFFSET ?= 0x50000000
ENTRY_OFFSET ?= 0x0

CLEANFILES = \
	$(BUILD_DIR)/pvh_payload.bin \
	$(BUILD_DIR)/pvh_shim.o \
	$(BUILD_DIR)/pvh_payload.o \
	$(BUILD_DIR)/pvh_shim.ld \
	$(OUTPUT_ELF)

.PHONY: pvh-shim-elf

all-local: pvh-shim-elf

pvh-shim-elf:
	@if [ -z "$(INPUT_BIN)" ]; then \
		echo "INPUT_BIN is required" >&2; \
		exit 1; \
	fi
	@if [ ! -f "$(INPUT_BIN)" ]; then \
		echo "Input kernel binary not found: $(INPUT_BIN)" >&2; \
		exit 1; \
	fi
	cp "$(INPUT_BIN)" "$(BUILD_DIR)/pvh_payload.bin"
	cd "$(BUILD_DIR)" && \
	objcopy -I binary -O elf64-x86-64 -B i386:x86-64 pvh_payload.bin pvh_payload.o && \
	objcopy \
		--rename-section .data=.payload,alloc,load,readonly,data,contents \
		--redefine-sym _binary_pvh_payload_bin_start=payload_start \
		--redefine-sym _binary_pvh_payload_bin_end=payload_end \
		--redefine-sym _binary_pvh_payload_bin_size=payload_size \
		pvh_payload.o
	$(CC) -c -m64 -nostdlib -ffreestanding -fno-stack-protector -fno-pie -no-pie \
		-fno-asynchronous-unwind-tables -fno-unwind-tables -fno-exceptions \
		-DPAYLOAD_ENTRY_OFFSET=$(ENTRY_OFFSET) \
		"$(srcdir)/pvh_shim.c" -o "$(BUILD_DIR)/pvh_shim.o"
	{ \
		echo "ENTRY(pvh_entry)"; \
		echo; \
		echo "PHDRS {"; \
		echo "  note PT_NOTE FLAGS(4);"; \
		echo "  text PT_LOAD FLAGS(5);"; \
		echo "}"; \
		echo; \
		echo "SECTIONS {"; \
		echo "  . = $(LOAD_OFFSET);"; \
		echo; \
		echo "  .note.Xen : {"; \
		echo "    KEEP(*(.note.Xen))"; \
		echo "  } :note"; \
		echo; \
		echo "  .text : ALIGN(16) {"; \
		echo "    *(.text*)"; \
		echo "  } :text"; \
		echo; \
		echo "  .rodata : ALIGN(16) {"; \
		echo "    *(.rodata*)"; \
		echo "  } :text"; \
		echo; \
		echo "  .payload : ALIGN(4096) {"; \
		echo "    __payload_load_start = .;"; \
		echo "    KEEP(*(.payload))"; \
		echo "    __payload_load_end = .;"; \
		echo "  } :text"; \
		echo; \
		echo "  /DISCARD/ : {"; \
		echo "    *(.comment)"; \
		echo "    *(.note.GNU-stack)"; \
		echo "  }"; \
		echo "}"; \
	} > "$(BUILD_DIR)/pvh_shim.ld"
	ld -m elf_x86_64 -nostdlib -z max-page-size=0x1000 -T "$(BUILD_DIR)/pvh_shim.ld" \
		"$(BUILD_DIR)/pvh_shim.o" "$(BUILD_DIR)/pvh_payload.o" -o "$(OUTPUT_ELF)"
	@echo "Built PVH-capable VTL1 shim ELF: $(OUTPUT_ELF)"
	@echo "  Input payload : $(INPUT_BIN)"
	@echo "  Entry offset  : $(ENTRY_OFFSET)"
	@echo "  Load offset   : $(LOAD_OFFSET)"
	@echo "  Output type   : $$(file -b "$(OUTPUT_ELF)")"
