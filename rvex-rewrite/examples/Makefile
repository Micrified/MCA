# This Makefile can be used with parameters ISSUE WIDTH, DYNAMIC, DYNAMIC_CORE,
# COMPILER and LIMMH_PREV, documented below.

# It can also be included from different directories for different platforms.
# In this case, the following things should be defined by the calling makefile;
#   TOOLS - point to tools directory in repo w.r.t. calling makefile
#   GEN_EXAMPLES - point to the directory in which this makefile resides
#   EXECUTABLES - list of platform-specific programs to compile
#   OBJECTS - list of platform-specific object files to build and link
#   TARGETS - list of platform-specific make targets for make help
#   CLEAN - list of platform-specific file(type)s to clean

# Parallel execution is not supported due to the _start.o file, which differs
# for different targets while the filename is shared.
.NOTPARALLEL:

# Issue width; must be 2, 4 or 8. Default = 8.
ifndef ISSUE_WIDTH
ISSUE_WIDTH = 8
endif
DEFS += ISSUE=$(ISSUE_WIDTH)

# Bundle alignment requirement. Must be 1, 2, 4 or 8 (and at most ISSUE_WIDTH).
# Default is $(ISSUE_WIDTH) to disable stop bits.
ifndef BUNDLE_ALIGN
BUNDLE_ALIGN = $(ISSUE_WIDTH)
# NOTE: This was changed to 2 in ancient times for some reason. Please refrain
# from changing the defaults in this file; they should always correspond to the
# default core configuration ( = what you get when you configure with core_cfg()
# without parameters). Platform specific core configurations should be changed
# in the platform specific makefiles.
endif

# Filename to give to io.c. replace the dot (.) by an underscore here,
# the linker wants that.
# You will need to add the file to the .dep file and convert it to elf
# yourself.
ifndef FILENAME
FILENAMEDEF =
else
FILENAMEDEF = -DFILENAME=$(FILENAME)
endif

# Which libraries to link against. We have the uClibc library for use on 
# Linux (2.0 nommu).
# Or newlib for use on the bare-metal core. For newlib you might need 
# to include an application-specific version of io.c that includes your input 
# file(s). io.c contains a printf implementation that writes to the UART and 
# stores all output in a circular buffer in memory. 
# This can be used by xSTsim to read the output after the program exits.
ifdef RVEXLIB_UCLIBC
INCLUDES = -I/data/uCLinux/generic_binary/uCLinux/uClibc/include \
 -I/data/uCLinux/generic_binary/uCLinux/linux-2.0.x/include/ \
 -I/data/tools/st200/ST200R7.3.0/include/ \
 -I/data/tools/st200/ST200R7.3.0/target/core/st220
LDFLAGS = --no-demangle /data/uCLinux/generic_binary/uCLinux/uClibc/lib/crt0.o \
 -L/data/uCLinux/generic_binary/uCLinux/uClibc/lib -lm -lc floatlib.o
endif

ifdef RVEXLIB_NEWLIB_FILE
DEFS+= IO_LINK_FILE
INCLUDES = -I/data/other/newlib/build/rvex/rvex-elf32/include \
 -I/data/tools/st200/ST200R7.3.0/include/ \
 -I/data/tools/st200/ST200R7.3.0/target/core/st220
LDFLAGS = matrix.txt.elf -Telf32rvex.x --no-demangle  --defsym end=__STACK_START -L/data/other/newlib/build/rvex/rvex-elf32/lib -lm -lc -lnosys floatlib.o
endif

ifdef RVEXLIB_NEWLIB_NOFILE
INCLUDES = -I/data/other/newlib/build/rvex/rvex-elf32/include \
 -I/data/tools/st200/ST200R7.3.0/include/ \
 -I/data/tools/st200/ST200R7.3.0/target/core/st220
LDFLAGS = -Telf32rvex.x --no-demangle --defsym end=__STACK_START -L/data/other/newlib/build/rvex/rvex-elf32/lib -lm -lc -lnosys floatlib.o
endif


# Generic binary behavior. Must be one of the following;
#   false     - compile for the specified issue width only.
#   true      - alias for true-O1.
#   true-O0   - run vexparse prior to assembly with --resched --O0
#   true-O1   - run vexparse prior to assembly with --resched --O1
#   true-O2   - run vexparse prior to assembly with --resched --O2
#   true-noresched - run vexparse prior to assembly without --resched
#   true-nofix - do not run vexparse prior to assembly.
# Default = true-O1.
ifndef DYNAMIC
DYNAMIC = true-O1
endif
ifeq ($(DYNAMIC), true)
override DYNAMIC = true-O1
endif
VEXPARSE_ENABLE = false
VEXPARSE_FLAGS = 
ifeq ($(DYNAMIC), true-O0)
VEXPARSE_ENABLE = true
VEXPARSE_FLAGS = --resched --O0
else ifeq ($(DYNAMIC), true-O1)
VEXPARSE_ENABLE = true
VEXPARSE_FLAGS = --resched --O1
else ifeq ($(DYNAMIC), true-O2)
VEXPARSE_ENABLE = true
VEXPARSE_FLAGS = --resched --O2
else ifeq ($(DYNAMIC), true-noresched)
VEXPARSE_ENABLE = true
endif

ifneq ($(DYNAMIC), false)
override DYNAMIC = true
ifndef DYNAMIC_CORE
DYNAMIC_CORE=true
endif
else
ifndef DYNAMIC_CORE
DYNAMIC_CORE=false
endif
endif

# Anything other than false enables debugging symbols and disables
# optimizations.
ifndef DEBUG
DEBUG = false
endif

# Compiler to use, must be HP, GCC or ST200. Default = HP.
ifndef COMPILER
COMPILER = HP
endif

# Whether LIMMH from previous syllable pair is supported by the core
# (limmhFromPreviousPair in the rvex CFG vector). Default = false.
ifndef LIMMH_PREV
LIMMH_PREV = false
endif

# Define stuff for this makefile when called on its own (not included).
ifndef EXECUTABLES
EXECUTABLES = 
endif
ifndef OBJECTS
OBJECTS = rvex-simrvex.o simrvex_stubs.o
endif
ifndef GEN_EXAMPLES
GEN_EXAMPLES = .
endif
ifndef START
START = default_start
endif

# Determine borrow configuration.
BORROW01   = 1.0
ifeq ($(LIMMH_PREV), true)
BORROW23   = .3,0.2,1
BORROW4567 = .5,2.4,3.7,4.6,5
else
BORROW23   = .3.2
BORROW4567 = .5.4.7.6
endif
ifeq ($(ISSUE_WIDTH), 2)
BORROW = $(BORROW01).
else ifeq ($(ISSUE_WIDTH), 4)
BORROW = $(BORROW01)$(BORROW23)
else
BORROW = $(BORROW01)$(BORROW23)$(BORROW4567)
endif

# Determine lane resource configuration.
#   Bit 0 = ALU
#   Bit 1 = MUL
#   Bit 2 = MEM
#   Bit 3 = BR
ifndef LANECONFIG
ifeq ($(ISSUE_WIDTH), 2)
ifeq ($(DYNAMIC_CORE), false)
 LANECONFIG = 7B
else
 LANECONFIG = FB
endif
else ifeq ($(ISSUE_WIDTH), 4)
ifeq ($(DYNAMIC_CORE), false)
 LANECONFIG = 337B
else
 LANECONFIG = FBFB
endif
else
ifeq ($(DYNAMIC_CORE), false)
 LANECONFIG = 3333337B
else
 LANECONFIG = FBFBFBFB
endif
endif
endif

# Empty program.
EXECUTABLES += nothing

# Powerstone benchmarks.
POWERSTONE = qurt crc bcnt blit compress des engine fir g3fax jpeg pocsag ucbqsort v42 
#POWERSTONE += whetstone auto
EXECUTABLES += $(POWERSTONE)

# Random other applications.
EXECUTABLES += ucbqsort-fast adpcm1 dft itver2 itver2-repeat matrix memwrite\
	soma x264 uart xstsimframebuffer all-at-once convolution greyscale dijkstra chanvese gauss_parallel

# List of platform-agnostic (generic) programs which run and complete without
# interaction, and test for success/failure. On success, main() should return
# 0.
BENCH_EXECUTABLES  = adpcm bcnt blit crc engine fir g3fax itver2 jpeg matrix des compress
BENCH_EXECUTABLES += pocsag qurt soma ucbqsort v42 x264 

# Toolchain setup.
ifndef TOOLS
TOOLS = ../tools
endif
BUILD = $(TOOLS)/rvex-elf32-32bit/bin
HOSTCC = gcc
OBJCOPY = $(BUILD)/rvex-elf32-objcopy
OBJDUMP = $(BUILD)/rvex-elf32-objdump
SED = sed
CP = cp
MV = mv
RM = rm -f
MKDIR = mkdir
PYTHON = python3
VEXPARSE = $(PYTHON) $(TOOLS)/vexparse/main.py
SIM = ADAPTOR_CONFIG=${GEN_EXAMPLES}/plugin.conf $(TOOLS)/sim/bin/simrvex
GDB = $(BUILD)/rvex-elf32-gdb
PLATFORM_SRC = src
GENERIC_SRC = $(GEN_EXAMPLES)/src

# Assembler setup.
AS = $(BUILD)/rvex-elf32-as
ASFLAGS = --issue $(ISSUE_WIDTH) --borrow $(BORROW) --config $(LANECONFIG) --padding $(BUNDLE_ALIGN)
ifneq ($(DYNAMIC), false)
ASFLAGS += -u
endif
ifneq ($(DEBUG), false)
ASFLAGS += -g
endif
ifneq ($(AUTOSPLIT), false)
ASFLAGS += --autosplit
endif

# Linker setup.
LD = $(BUILD)/rvex-elf32-ld
ifneq ($(DEBUG), false)
ASFLAGS += -g
endif

# Compiler setup.
ifeq ($(COMPILER), HP)
CC = $(TOOLS)/vex-3.43/bin/cc
CFLAGS = -I$(GEN_EXAMPLES)/src -fno-xnop -fexpand-div -fmm=$(GEN_EXAMPLES)/pipe_1_$(ISSUE_WIDTH)_fw.mm
ifeq ($(DEBUG), false)
CFLAGS += -O2
else
CFLAGS += -g
endif

else ifeq ($(COMPILER), GCC)
CC = $(TOOLS)/build/bin/vex-gcc
CFLAGS = -I$(GEN_EXAMPLES)/src
ifeq ($(DEBUG), false)
CFLAGS += -O3
else
CFLAGS += -g
endif

else
FPLIB=libcfpi-st220.cc.a
CFLAGS = -I$(GEN_EXAMPLES)/src -mcore=st220 -EB -fshort-double -fno-dismissible-load \
-fno-exceptions -mno-auto-prefetch -std=c99 -fno-builtin $(INCLUDES)
ifeq ($(ISSUE_WIDTH), 8)
CC=/shares/group/ce-rvex/tools/builds/open64_8issue_16UNROLL/bin/st200-gcc
ifeq ($(DEBUG), false)
CFLAGS += -O3 -CG:LAO_activation=0
else
CFLAGS += -g
endif
else ifeq ($(ISSUE_WIDTH), 4)
CC=/shares/group/ce-rvex/tools/builds/open64_4issue/bin/st200-gcc
ifeq ($(DEBUG), false)
CFLAGS += -O3
else
CFLAGS += -g
endif
else
CC=/shares/group/ce-rvex/tools/builds/open64_2issue/bin/st200-gcc
ifeq ($(DEBUG), false)
CFLAGS += -O3 -CG:LAO_activation=0
else
CFLAGS += -g
endif
endif
endif

# Make magic.
.SUFFIXES:
.PRECIOUS: %.o %.s *.s %.elf %.xst.elf %.srec %.disas

.PHONY: help list-executables
help:
	@echo ""
	@echo " Compiles programs for the rvex. The following targets are available."
	@echo ""
	@echo "  make all                 builds all programs"
	@echo "  make clean               cleans output files"
	@echo "  make <program>           buils the given program"
	@echo "  make sim-<program>       runs the given program using simrvex"
	@for target in $(TARGETS) ; do \
		echo "  $$target" ; \
	done
	@echo ""
	@echo " You can use the following modifies when building (be careful to spell them"
	@echo " correctly!)"
	@echo ""
	@echo "  make <target> ISSUE_WIDTH=<2|4|8>                (default = 8)"
	@echo "  make <target> DYNAMIC=<(see Makefile)>           (default = true-O1)"
	@echo "  make <target> DYNAMIC_CORE=<true|false>          (default = same as DYNAMIC)"
	@echo "  make <target> COMPILER=<HP|GCC|ST200>            (default = HP)"
	@echo "  make <target> LIMMH_PREV=<true|false>            (default = true)"
	@echo "  make <target> DEFS=<list of preprocessor defs>   (default = <none>)"
	@echo ""
	@echo " NOTE: in general, you should clean before building a program using a different"
	@echo " target or with different modifiers; dependency checking is not 100%."
	@echo ""
	@echo " The following programs are available:"
	@echo ""
	@for exec in $(EXECUTABLES) ; do \
		echo "  $$exec" ; \
	done
	@echo ""

list-executables:
	@echo ""
	@echo " The following programs are available:"
	@echo ""
	@for exec in $(EXECUTABLES) ; do \
		echo "  $$exec" ; \
	done
	@echo ""

.PHONY: all
all: $(EXECUTABLES)

# How to compile platform-specific sources;
%.s: $(PLATFORM_SRC)/%.c
	$(CC) $(CFLAGS) $(patsubst %,-D%,$(DEFS) $(XSTSIM)) -S $<
ifeq ($(COMPILER), HP)
	$(SED) -i -e "s/^\(\.stab[sn][^\w].*\);$$/\1/" $@
endif

# Where to get platform-specific assembly files and how to preprocess them;
ifeq ($(COMPILER), HP)
%.s: $(PLATFORM_SRC)/%.S
	$(CC) $(CFLAGS) $(patsubst %,-D%,$(DEFS) $(XSTSIM)) -E $< > $@
	$(SED) -i -e "s/^\(\.stab[sn][^\w].*\);$$/\1/" $@
else
%.s: $(PLATFORM_SRC)/%.S
	$(CC) $(CFLAGS) $(patsubst %,-D%,$(DEFS) $(XSTSIM)) -E $< -o $@
endif

# How to compile generic sources;
io.s: $(GENERIC_SRC)/io.c
	$(CC) $(CFLAGS) -I/data/other/newlib/build/rvex/rvex-elf32/include \
	-I/data/tools/st200/ST200R7.3.0/include/ \
	-I/data/tools/st200/ST200R7.3.0/target/core/st220 \
	$(patsubst %,-D%,$(DEFS) $(XSTSIM)) -S $<

%.s: $(GENERIC_SRC)/%.c
	$(CC) $(CFLAGS) $(patsubst %,-D%,$(DEFS) $(XSTSIM)) -S $<
ifeq ($(COMPILER), HP)
	$(SED) -i -e "s/^\(\.stab[sn][^\w].*\);$$/\1/" $@
endif

# Where to get generic assembly files and how to preprocess them;
ifeq ($(COMPILER), HP)
%.s: $(GENERIC_SRC)/%.S
	$(CC) $(CFLAGS) $(patsubst %,-D%,$(DEFS) $(XSTSIM)) -E $< > $@
	$(SED) -i -e "s/^\(\.stab[sn][^\w].*\);$$/\1/" $@
else
%.s: $(GENERIC_SRC)/%.S
	$(CC) $(CFLAGS) $(patsubst %,-D%,$(DEFS) $(XSTSIM)) -E $< -o $@
endif

# Always compile VEXdiv with HP
VEXdiv.s: $(GENERIC_SRC)/VEXdiv.c
	$(TOOLS)/vex-3.43/bin/cc -I$(GEN_EXAMPLES)/src -fno-xnop -fexpand-div -fmm=$(GEN_EXAMPLES)/pipe_1_$(ISSUE_WIDTH)_fw.mm \
	-S $< -o $@

#Dirty tricks to force other FP library in case we're using Open64
.PHONY: FORCE
FORCE:

ifeq ($(COMPILER), O64)
ifeq ($(ISSUE_WIDTH), 4)
floatlib.o: IFR4_stat/LIBFP/libcfpi-st220.cc.a FORCE
	cp $< $@
else ifeq ($(ISSUE_WIDTH), 8)
floatlib.o: IFR8_stat/LIBFP/libcfpi-st220.cc.a FORCE
	cp $< $@
endif
endif

# How to assemble;
%.o: %.s
ifeq ($(VEXPARSE_ENABLE), true)
	@# This right here is really f'ing ugly, but for some reason the labels in
	@# _start.s are treated differently from the labels in the other files, and
	@# vexparse doesn't like it.
	@if [ "$(findstring _start.s,$<)" != "_start.s" ]; then \
		echo "$(CP) $< $(patsubst %.s,%.orig.s,$<)"; \
		$(CP) $< $(patsubst %.s,%.orig.s,$<); \
		echo "$(VEXPARSE) $(patsubst %.s,%.orig.s,$<) $(VEXPARSE_FLAGS) --borrow $(BORROW) --config $(LANECONFIG) -o $<"; \
		$(VEXPARSE) $(patsubst %.s,%.orig.s,$<) $(VEXPARSE_FLAGS) --borrow $(BORROW) --config $(LANECONFIG) -o $<; \
	fi
endif
	$(AS) $(ASFLAGS) $< -o $@

# How to convert objects with a main() such that they can be used as
# subprograms in a bigger program (prefixes global symbols with the object
# name);
%-sub.o: %.o
	$(OBJDUMP) -t $< | grep -E '^[0-9a-fA-F]{8} g' | sed -r 's/^.* (\w+)$$/\1 $(patsubst %.o,%,$<)_\1/g' > $(patsubst %.o,%.syms,$<)
	$(OBJCOPY) --redefine-syms $(patsubst %.o,%.syms,$<) $< $@

# Special rule for _start.o, may be overwritten target-specifically;
.PHONY: _start.o-%
_start.o-%: default_start.o
	$(RM) _start.o
	$(CP) default_start.o _start.o

# How to link;
.SECONDEXPANSION:
%.elf: _start.o-% %.o $$(OBJECTS) $$(shell $$(PYTHON3) $$(GEN_EXAMPLES)/deps.py -p$$(PLATFORM_SRC) -p$$(GENERIC_SRC) $$@ $$(OBJECTS))
	$(LD) _start.o $(filter-out $<,$^) -o $@ $(LDFLAGS)

# How to link all BENCH_EXECUTABLES together so they all run from a single
# main():
all-at-once.elf: _start.o-all-at-once $$(patsubst %,%-sub.o,$$(BENCH_EXECUTABLES)) $$(OBJECTS) $$(shell $$(PYTHON3) $$(GEN_EXAMPLES)/deps.py -p$$(PLATFORM_SRC) -p$$(GENERIC_SRC) $$(BENCH_EXECUTABLES) $$(OBJECTS))
	$(PYTHON3) $(GEN_EXAMPLES)/all-at-once.py $(BENCH_EXECUTABLES) > all-at-once.s
	$(AS) $(ASFLAGS) all-at-once.s -o all-at-once.o
	$(LD) _start.o all-at-once.o $(filter-out $<,$^) -o $@

# How to generate an srec;
%.srec: %.elf
	$(OBJCOPY) -O srec $< $@

# How to disassemble;
%.disas: %.elf
	$(OBJDUMP) -d $< > $@

#Create binary file to upload using GRMON
%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

# Default targets for applications;
.PHONY: $(EXECUTABLES)
$(EXECUTABLES):
	$(MAKE) $@.srec $@.disas

# How to run simrvex
sim-%: %.elf
	${SIM} $<

.PHONY: simtestall
simtestall: simtestall-clean $(POWERSTONE:%=simtest-%)

.PHONY: simtestall-clean
simtestall-clean:
	echo -n "" > simtestall

#The Powerstone programs all return 0xdeadbeef. 
#We take the last register contents using tail and grep for that value in r3 (return value register).
simtest-% : %.elf
	@${SIM} -t1,0 $^|tail -n 40 | grep "r03 = 0xdeadbeef";\
	if [ $$? != 0 ] ; then \
	echo "Program returned unexpected exit code" ; echo $* >> simtestall; echo -e "\t\tError!" >> simtestall; \
	else \
	echo "Program Finished Successfully" ; echo $* >> simtestall; echo -e "\t\tOK" >> simtestall;  \
	fi

.PHONY:simlogall
simlogall: $(POWERSTONE:%=simlog-%)

simlog-% : %.elf
	${SIM} $< > $@

simtrace-% : %.elf
	${SIM} -t1,0 $< > $@

.PHONY: clean
clean:
	$(RM) *.o *.s *.elf *.srec *.disas *.syms $(CLEAN)
ifdef CLEAN_DIR
	$(RM) -r $(CLEAN_DIR)
endif

