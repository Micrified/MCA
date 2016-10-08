
# Please don't delete random files, make.
.SUFFIXES:
.PRECIOUS: %.o %.s %.sv %.S %.c %.elf %.xst.elf %.srec %.disas

# Where the workspace directory is.
WORKSPACE  = /home/user/workspace

# Where the sources are located.
SRC_USER   = ../../../src
SRC_UTILS  = $(WORKSPACE)/assignment2/utils
SRC_RVRW   = $(WORKSPACE)/rvex-rewrite/examples/src

# All header files in the source directory. These are used as dependencies for
# all C sources. This adds more dependencies than strictly necessary, but it's
# a lot easier than generating the dependencies properly, and this is intended
# for only small programs anyway.
HDR_DEPS   = $(shell find $(SRC_USER) | grep "\.h$$")

# Where the compilation configuration file is.
CCONFIG    = $(SRC_USER)/config.compile

# Where the tools are located.
RVRW_TOOLS = $(WORKSPACE)/rvex-rewrite/tools
PARSECCFG  = python3 $(WORKSPACE)/tools/scripts/parse_compile_config.py $(CCONFIG) $(CONTEXT_ID)
CC         = $(RVRW_TOOLS)/vex-3.43/bin/cc
VEXPARSE   = python3 $(RVRW_TOOLS)/vexparse/main.py
AS         = rvex-as
LD         = rvex-ld
OBJDUMP    = rvex-objdump
OBJCOPY    = rvex-objcopy

# Objects to compile.
TARGETS += _start
TARGETS += common
TARGETS += bcopy
TARGETS += floatlib
TARGETS += record
TARGETS += $(shell $(PARSECCFG))

# Preprocessor definitions.
DEFS += ISSUE=$(ISSUE_WIDTH)

# Common flags for the VEX compiler.
CFLAGS += -I$(SRC_USER)
CFLAGS += -I$(SRC_UTILS)
CFLAGS += -I$(SRC_RVRW)
CFLAGS += -I$(shell pwd)
CFLAGS += -fno-xnop
CFLAGS += -fexpand-div
CFLAGS += -c99inline
CFLAGS += -fmm=config.mm

# Flags for vexparse.
VPFLAGS += --resched
VPFLAGS += -O1
VPFLAGS += --borrow $(BORROW)
VPFLAGS += --config $(LANECONFIG)

# Flags for the assembler.
ASFLAGS += --issue $(ISSUE_WIDTH)
ASFLAGS += --borrow $(BORROW)
ASFLAGS += --config $(LANECONFIG)
ASFLAGS += --padding $(BUNDLE_ALIGN)
ASFLAGS += --autosplit

# Flags for the linker.
LDFLAGS += -Tconfig.x

# Build all.
.PHONY: all
all: out.srec out.disas

# How to compile C files.
%.s: $(SRC_USER)/%.c $(CCONFIG) $(HDR_DEPS)
	$(CC) $(CFLAGS) `$(PARSECCFG) $*` $(patsubst %,-D%,$(DEFS)) -S $<
	sed -i -e "s/^\(\.stab[sn][^\w].*\);$$/\1/" $@
%.s: $(SRC_UTILS)/%.c $(CCONFIG)
	$(CC) $(CFLAGS) `$(PARSECCFG) $*` $(patsubst %,-D%,$(DEFS)) -S $<
	sed -i -e "s/^\(\.stab[sn][^\w].*\);$$/\1/" $@

# How to preprocess hand-written assembly files.
%.s: $(SRC_USER)/%.S $(CCONFIG) $(HDR_DEPS)
	$(CC) $(CFLAGS) $(patsubst %,-D%,$(DEFS)) -E $< > $@
	sed -i -e "s/^\(\.stab[sn][^\w].*\);$$/\1/" $@
%.s: $(SRC_UTILS)/%.S $(CCONFIG)
	$(CC) $(CFLAGS) $(patsubst %,-D%,$(DEFS)) -E $< > $@
	sed -i -e "s/^\(\.stab[sn][^\w].*\);$$/\1/" $@

# How to reschedule assembly files as generic binaries.
%.sv: %.s
	$(VEXPARSE) $(VPFLAGS) $< -o $@

# How to assemble.
ifeq ($(GENERIC_BINARY), true)
%.o: %.sv
	$(AS) $(ASFLAGS) -u $< -o $@
else
%.o: %.s
	$(AS) $(ASFLAGS) $< -o $@
endif

# Each powerstone program has its own main() and sometimes some rather generic
# global variables. In order to compile multiple powerstone programs into one,
# the global symbols need to be renamed to something unique. This target
# prefixes all the globals defined in an object with the C filename and an
# underscore.
%-sub.o: %.o
	$(OBJDUMP) -t $< \
		| grep -E '^[0-9a-fA-F]{8} g' \
		| sed -r 's/^.* ([a-zA-Z0-9\._-\?]+)$$/\1 $(patsubst %.o,%,$<)_\1/g' \
		> $(patsubst %.o,%.syms,$<)
	$(OBJCOPY) --redefine-syms $(patsubst %.o,%.syms,$<) $< $@

# How to link.
out.elf: $(patsubst %,%.o,$(TARGETS))
	$(LD) $(LDFLAGS) $^ -o $@

# How to generate an S-record file.
out.srec: out.elf
	$(OBJCOPY) -O srec $< $@

# How to generate disassembly.
out.disas: out.elf
	$(OBJDUMP) -d $< > $@

# How to clean.
.PHONY: clean
clean:
	rm -f *.s *.sv *.o *.syms out.elf out.srec out.disas

