SRCDIR=$(CURDIR)
TOP_DIR := $(abspath $(SRCDIR)/../../..)
MOCK_PROFILE=fedora-43-x86_64
KERNEL_VERSION=6.19.6
KERNEL_VERSION_TAG=fc43
STAGING_DIR=$(TOP_DIR)/build/stage/fedora-kernel
OUT_DIR=$(SRCDIR)/out
BUILD_HOST_KERNEL_RELEASE := $(shell uname -r)
ARCH := $(shell uname -m)

build-src-tarball:
	@mkdir -p $(STAGING_DIR)
	@cp /boot/config-$(BUILD_HOST_KERNEL_RELEASE) ~/workspaces/linux-$(KERNEL_VERSION)/.config
	@tar -C ~/workspaces -cJf $(STAGING_DIR)/linux-$(KERNEL_VERSION).tar.xz linux-$(KERNEL_VERSION)

build-src-rpm:
	@mkdir -p $(STAGING_DIR)
	@mock -r $(MOCK_PROFILE) \
		--buildsrpm \
		--spec $(SRCDIR)/SPECS/kernel.spec \
		--sources $(STAGING_DIR)
	@cp /var/lib/mock/$(MOCK_PROFILE)/result/kernel-$(KERNEL_VERSION)-*.$(KERNEL_VERSION_TAG).src.rpm $(STAGING_DIR)/

build-rpm:
	@mock -r $(MOCK_PROFILE) \
		--rebuild $(STAGING_DIR)/kernel-$(KERNEL_VERSION)-*.$(KERNEL_VERSION_TAG).src.rpm
	@mkdir -p $(OUT_DIR)/$(ARCH)
	@cp /var/lib/mock/$(MOCK_PROFILE)/result/kernel-$(KERNEL_VERSION)-*.$(KERNEL_VERSION_TAG).$(ARCH).rpm $(OUT_DIR)/$(ARCH)/

mock-init:
	@mock -r $(MOCK_PROFILE) --init

mock-set-default:
	@sudo rm -f /etc/mock/default.cfg
	@sudo ln -s /etc/mock/$(MOCK_PROFILE).cfg /etc/mock/default.cfg

clean:
	@mock -r $(MOCK_PROFILE) clean

scrub: clean
	@rm -rf $(STAGING_DIR) $(OUT_DIR)
