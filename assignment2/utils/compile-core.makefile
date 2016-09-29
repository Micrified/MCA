
# Please don't delete random files, make.
.SUFFIXES:
.PRECIOUS: %.o %.s %.sv %.S %.c %.elf %.xst.elf %.srec %.disas

# Where the workspace directory is.
WORKSPACE = /home/user/workspace

# Where the sources are located.
SRC_POWERSTONE = $(WORKSPACE)/assignment2/powerstone
SRC_UTILS      = $(WORKSPACE)/assignment2/utils
SRC_RVRW       = $(WORKSPACE)/rvex-rewrite/examples/src

# Where the tools are located.
RVRW_TOOLS = $(WORKSPACE)/rvex-rewrite/tools
CC       = $(RVRW_TOOLS)/vex-3.43/bin/cc
VEXPARSE = python3 $(RVRW_TOOLS)/vexparse/main.py
AS       = rvex-as
LD       = rvex-ld
OBJDUMP  = rvex-objdump
OBJCOPY  = rvex-objcopy

# Preprocessor definitions.
DEFS += ISSUE=$(ISSUE_WIDTH)

# Flags for the VEX compiler.
CFLAGS += -I$(SRC_POWERSTONE)
CFLAGS += -I$(SRC_UTILS)
CFLAGS += -I$(SRC_RVRW)
CFLAGS += -I$(shell pwd)
CFLAGS += -fno-xnop
CFLAGS += -fexpand-div
CFLAGS += -c99inline
CFLAGS += -fmm=config.mm

# Flags for vexparse.
VPFLAGS += --resched
VPFLAGS += --O1
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

# How to symlink sources from powerstone.
%.c: $(SRC_POWERSTONE)/%.c
	ln -s $< $@

# How to symlink sources from utils.
%.c: $(SRC_UTILS)/%.c
	ln -s $< $@
%.S: $(SRC_UTILS)/%.S
	ln -s $< $@

# How to compile C files.
%.s: %.c
	$(CC) $(CFLAGS) $(patsubst %,-D%,$(DEFS)) -S $<
	sed -i -e "s/^\(\.stab[sn][^\w].*\);$$/\1/" $@

# How to preprocess hand-written assembly files.
%.s: %.S
	$(CC) $(CFLAGS) $(patsubst %,-D%,$(DEFS)) -E $< > $@
	sed -i -e "s/^\(\.stab[sn][^\w].*\);$$/\1/" $@

# How to reschedule assembly files to fix long immediate problems.
%.sv: %.s
	$(VEXPARSE) $(VPFLAGS) $< -o $@

# How to assemble. To enable vexparse, change the dependency from %.s to %.sv.
%.o: %.s
	$(AS) $(ASFLAGS) $< -o $@

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

