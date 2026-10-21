# Check, build and boot the bare-metal images of loup-cmd-bare-timer.
#
# One image per board: x86_64 (QEMU pc; package.lppkg at the root) and
# aarch64 (QEMU virt; boards/aarch64/package.lppkg). On Linux x86-64 `loup`
# is the self-hosted driver, which builds images; `loup-bootstrap` (Stage0)
# type-checks them.

APP            ?= timer
LOUP           ?= loup
LOUP_BOOTSTRAP ?= loup-bootstrap
BUILD_DIR      ?= build
ARCHS          := x86_64 aarch64
ARCH           ?= x86_64
IMAGES         := $(foreach a,$(ARCHS),$(BUILD_DIR)/$(APP)-$(a).elf)
SOURCES        := package.lppkg boards/aarch64/package.lppkg \
                  $(wildcard linker/*.ld) $(shell find source -name '*.lpfree')

# The directory holding a board's manifest.
board_dir = $(if $(filter x86_64,$(1)),.,boards/$(1))

.PHONY: all check build boot run ci clean

all: build

# Type-check each board's entry file and every module it imports. The
# "marshals a struct by value" warnings on the interrupt handlers' frame
# parameter are expected (see the README).
check:
	$(LOUP_BOOTSTRAP) check --no-color
	cd boards/aarch64 && $(LOUP_BOOTSTRAP) check --no-color

# Both images (needs Linux x86-64, clang and ld.lld).
build: $(IMAGES)

# `loup build` keeps a fingerprint next to the image and skips the build
# when it matches; for boards/aarch64 the fingerprint does not cover the
# sources in ../../source, so it is removed whenever make decides to rebuild.
$(BUILD_DIR)/$(APP)-%.elf: $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	@rm -f $@.loupbuild.fp
	$(LOUP) build --target freestanding --arch $* -o $@ $(call board_dir,$*)

# End-to-end: boot each image under QEMU, wait for heartbeats, press keys,
# and compare the transcripts and exit statuses with tests/expected/
boot: $(IMAGES)
	bash tests/boot.sh $(BUILD_DIR)

# Boot one image with its serial port on this terminal, e.g.
# `make run ARCH=aarch64`. Keys go to the kernel; press q to quit.
run: $(BUILD_DIR)/$(APP)-$(ARCH).elf
	-scripts/qemu.sh $(ARCH) $<

# Everything CI runs.
ci: check build boot

clean:
	rm -rf $(BUILD_DIR) .temp boards/aarch64/.temp
