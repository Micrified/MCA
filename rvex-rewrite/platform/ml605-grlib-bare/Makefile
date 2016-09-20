
.PHONY: help
help: work
	@echo ""
	@echo " This platform is essentially grlib's LEON3 project for the ML605 board, with"
	@echo " the rvex processor and debug support UART added to it."
	@echo ""
	@echo " Synthesis and simulation have been verified to work with modelsim 10.2a and"
	@echo " Xilinx ISE 14.7. Xilinx ISE 13.4 is known NOT to synthesize correctly. Use"
	@echo " other versions at your own risk."
	@echo ""
	@echo " Make targets:"
	@echo ""
	@echo "  make sim-<prog>   : shorthand for cleaning and running all necessary targets"
	@echo "                      for modelsim simulation. Source both modelsim and xilinx"
	@echo "                      environment scripts first. <prog> may be set to one of the"
	@echo "                      known programs, listed below."
	@echo ""
	@echo "  make resim-<prog> : shorthand for recompiling and restarting simulation if"
	@echo "                      only already existing VHDL files have been changed."
	@echo ""
	@echo "  make synth        : shorthand for cleaning and running all necessary targets"
	@echo "                      for command-line based synthesis of the design using ISE."
	@echo "                      Source the ISE 14.7 environment script first."
	@echo ""
	@echo "  make ise          : launches the ISE GUI."
	@echo ""
	@echo "  make upload-<prog>: compiles the specified program, starts rvsrv if it is"
	@echo "                      not already running and uploads the program to the"
	@echo "                      core. Leaves the core reset at PC 0."
	@echo ""
	@echo "  make start-<prog> : same as upload-<prog>, but also starts the program."
	@echo ""
	@echo "  make trace-<prog> : uploads and traces a program using the hardware trace"
	@echo "                      unit."
	@echo ""
	@echo "  make gdb-<prog>   : compiles and uploads the specified program and then runs"
	@echo "                      gdb to debug it."
	@echo ""
	@echo "  make run-<prog>   : same as start-<prog>, but also waits for completion."
	@echo "                      Completion is detected when none of the context cycle"
	@echo "                      counters increment between two reads."
	@echo ""
	@echo "  make run-all      : calls run-<prog> for all executables."
	@echo ""
	@echo "  make server       : starts rvsrv."
	@echo ""
	@echo "  make stop         : stops rvsrv."
	@echo ""
	@echo "  make debug        : generates a script which can be sourced to set up the"
	@echo "                      rvd/rvsrv debugging environment; run \"source debug\""
	@echo "                      after calling this command."
	@echo ""
	@echo "  make monitor      : uses netcat to connect to the application interface of"
	@echo "                      rvsrv. Anything written by the application using puts"
	@echo "                      will be dumped to the terminal and you can send lines"
	@echo "                      to the program which can be read using getchar. Exit"
	@echo "                      using ctrl+C."
	@echo ""
	@echo "  make monitor-nobuf: same as monitor, but with line buffering and echo"
	@echo "                      disabled."
	@echo ""
	@echo "  make clean        : cleans most grlib and rvex compilation intermediate files."
	@echo ""
	@echo "  make clean-ex     : cleans only compilation intermediate files."
	@echo ""
	@echo "  make very-clean   : on top of clean, removes the ENTIRE grlib working"
	@echo "                      directory. This might contain modified source files - it"
	@echo "                      is your own responsibility to run make update-patch first"
	@echo "                      if so."
	@echo ""
	@echo "  make update-patch : cleans the working directory and generates the work.patch"
	@echo "                      file used to rebuild the working directory from the grlib"
	@echo "                      base project. This must be run if changes are made to the"
	@echo "                      files in work before committing to git."
	@cd examples && $(MAKE) --no-print-directory list-executables
	@echo " For convenience, you can also call the usual grlib makefile targets from this"
	@echo " file, by prefixing with gr-. The targets are listed below."
	@cd work && $(MAKE) --no-print-directory help | sed -e "s/make \([a-zA-Z0-9_-]*\)/ make gr-\1/"


#------------------------------------------------------------------------------
# Additional planahead options
#------------------------------------------------------------------------------

# Random seed for placer.
MAP_COST_TABLE = 2


#------------------------------------------------------------------------------
# GRLIB project management
#------------------------------------------------------------------------------

# Call the makefile in the grlib directory to download and patch grlib.
../../grlib/grlib-gpl-1.3.7-b4144:
	cd ../../grlib && $(MAKE) grlib-gpl-1.3.7-b4144

# Copies the base project from grlib into work and patches it.
work: ../../grlib/grlib-gpl-1.3.7-b4144
	@if [ -d work ]; then \
		touch work; \
		echo "Touched work directory for make..."; \
	else \
		cp -r ../../grlib/grlib-gpl-1.3.7-b4144/designs/leon3-xilinx-ml605 .; \
		mv ./leon3-xilinx-ml605 ./work; \
		cd work && patch -p1 < ../work.patch; \
		echo "Rebuilt work directory from patchfile..."; \
	fi

# Updates the patchfile based upon the differences between the grlib base
# project and the current contents of work. Kind of the inverse operation of
# the "work" target.
.PHONY: update-patch update-%.patch
update-patch: update-work.patch
update-%.patch: clean
	@cd work && $(MAKE) distclean
	diff -rupN --exclude="ram.srec" --exclude="ptag.vhd" \
		../../grlib/grlib-gpl-1.3.7-b4144/designs/leon3-xilinx-ml605/ work/ \
		> $(patsubst update-%,%,$@) ; true

# Cleans all grlib and rvex compilation intermediate files.
.PHONY: clean
clean: clean-ex
	-cd work && $(MAKE) distclean scripts-clean migclean
	rm -f work/*_beh.prj
	rm -f work/xilinx.log
	rm -f work/timing.twr
	rm -rf work/archive
	rm -f synth.patch

# Removes the entire working directory; use with care (because the work dir might contain
# source files as well, which may not have been put in the patch file yet).
.PHONY: very-clean
very-clean: clean
	rm -Irf work


#------------------------------------------------------------------------------
# GRLIB makefile chaining/shorthands
#------------------------------------------------------------------------------

ARCHIVE_TOOLS = ../../versions/tools
ARCHIVE_DIR = work/archive

# Chain to the grlib makefile.
gr-%: work
	@cd work && $(MAKE) $(patsubst gr-%,%,$@)

# Shorthand notations for simulating, as descibed in the grlib leon project
# readme. THIS DOES A LOT OF EXTRA WORK BECAUSE IT STARTS FROM SCRATCH. FIXME!
.PHONY: sim-%
sim-%: work compile-%
	$(ARCHIVE_TOOLS)/gen_platform_version_pkg.py $(ARCHIVE_DIR)
	cd work && $(MAKE) \
		distclean\
		migclean\
		scripts-clean\
		mig39\
		install-secureip\
		compile_xilinx_verilog_lib\
		compile.vsim\
		vsim\
		map_xilinx_verilog_lib\
		vsim-launch

# Like sim-%, but does a little less extra work.
.PHONY: resim-%
resim-%: work compile-%
	$(ARCHIVE_TOOLS)/gen_platform_version_pkg.py $(ARCHIVE_DIR)
	cd work && $(MAKE) \
		vsim\
		map_xilinx_verilog_lib\
		vsim-launch

# Runs synthesis. This also archives the core when it finishes generating.
.PHONY: synth
synth: work
	
	# Version management.
	$(MAKE) update-synth.patch
	$(ARCHIVE_TOOLS)/archive_platform_prepare.py $(ARCHIVE_DIR)
	rm -f synth.patch
	
	# Synthesis.
	cd work && $(MAKE) mig39 planahead MAP_COST_TABLE=$(MAP_COST_TABLE)
	
	# More version management.
	touch work/xilinx.log
	cat work/planahead/leon3-*/*.runs/synth_1/runme.log >> work/xilinx.log
	cat work/planahead/leon3-*/*.runs/impl_1/runme.log >> work/xilinx.log
	cat work/planahead/leon3-*/*.runs/impl_1/*.twr > work/timing.twr
	$(ARCHIVE_TOOLS)/archive_platform_complete.py $(ARCHIVE_DIR)

# Shorthand for launching ISE.
ise: work
	cd work && $(MAKE) \
		scripts-clean\
		migclean\
		mig39\
		ise-launch


#------------------------------------------------------------------------------
# C compilation and runtime targets
#------------------------------------------------------------------------------

# Cleans rvex compilation intermediate files.
.PHONY: clean-ex
clean-ex:
	cd examples && $(MAKE) clean

# Chains to the examples makefile to build the specified program and copy it to
# the s-record file read by the micron DDR memory model.
.PHONY: compile-%
compile-%:
	cd examples && $(MAKE) $(patsubst compile-%,copy-%,$@)

# Make sure the rvex debugging tools are compiled and generate source script
# for setting up the debugging environment.
.PHONY: debug
debug:
	cd examples && $(MAKE) $@
	cat ../../tools/debug-interface/debug > debug
	echo 'export RVD_OPT="-m$(shell pwd)/memory.map"' >> debug
	@echo ""
	@echo " Run \"source debug\" now..."
	@echo ""

# The following targets simply chain to the makefile in examples.
.PHONY: upload-%
upload-%:
	cd examples && $(MAKE) $@

.PHONY: start-%
start-%:
	cd examples && $(MAKE) $@

.PHONY: run-%
run-%:
	cd examples && $(MAKE) $@

.PHONY: trace-%
trace-%:
	cd examples && $(MAKE) $@

.PHONY: gdb-%
gdb-%:
	cd examples && $(MAKE) $@

.PHONY: server stop monitor monitor-nobuf
server stop monitor monitor-nobuf:
	cd examples && $(MAKE) $@

