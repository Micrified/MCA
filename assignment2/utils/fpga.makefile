
RVEX_REWRITE = /home/user/workspace/rvex-rewrite
SCRIPTS_DIR = /home/user/workspace/tools/scripts
RESULTS_DIR = ../results
PLATFORM = $(RVEX_REWRITE)/platform/ml605-grlib-bare
ARCHIVE_TOOLS = $(RVEX_REWRITE)/versions/tools
ARCHIVE_DIR = work/archive
GRLIB_DIR = $(RVEX_REWRITE)/grlib
CHAIN = cd work && $(MAKE) GRLIB=$(GRLIB_DIR)/grlib-gpl-1.3.7-b4144

WITH_ISE = source /home/user/workspace/tools/scripts/sx &&
WITH_SIM = source /home/user/workspace/tools/scripts/sm &&

.PHONY: all
all:
	@echo ""
	@echo "FPGA commands:"
	@echo ""
	@echo "make sim   - simulates the FPGA platform with the current source code"
	@echo "             in modelsim. Generates performance results including cache"
	@echo "             behavior, though with a simplified memory latency model."
	@echo ""
	@echo "make synth - synthesizes the design. Generates area utilization info"
	@echo "             and allows testing your design on the boardserver."
	@echo ""
	@echo "make run   - sends the design to the boardserver to measure performance."
	@echo "             Requires you to have already synthesized the design."
	@echo ""
	@echo "make clean - deletes all intermediate and output files. If you get weird"
	@echo "             errors from the other commands, running this and then"
	@echo "             trying again is not a bad idea."
	@echo ""

# Call the makefile in the grlib directory to download and patch grlib.
$(GRLIB_DIR)/grlib-gpl-1.3.7-b4144:
	cd $(GRLIB_DIR) && $(MAKE) grlib-gpl-1.3.7-b4144

# Copies the base project from grlib into work and patches it.
work: $(GRLIB_DIR)/grlib-gpl-1.3.7-b4144 config.vhd
	@if [ -d work ]; then \
		touch work; \
		echo "Touched work directory for make..."; \
	else \
		cp -r $(GRLIB_DIR)/grlib-gpl-1.3.7-b4144/designs/leon3-xilinx-ml605 .; \
		mv ./leon3-xilinx-ml605 ./work; \
		cd work && patch -p1 < $(PLATFORM)/work.patch; \
		rm -f config.vhd; \
		ln -s ../config.vhd config.vhd; \
		rm -rf rvex-lib; \
		ln -s /home/user/workspace/rvex-rewrite/lib rvex-lib; \
		echo "Rebuilt work directory from patchfile..."; \
	fi

# Copies archive manifest file.
archive-manifest: $(PLATFORM)/archive-manifest
	cp $(PLATFORM)/archive-manifest .

# Updates the patchfile based upon the differences between the grlib base
# project and the current contents of work. Kind of the inverse operation of
# the "work" target.
.PHONY: update-patch update-%.patch
update-patch: update-work.patch
update-%.patch: weak-clean
	@$(CHAIN) distclean
	diff -rupN --exclude="ram.srec" --exclude="ptag.vhd" \
		$(GRLIB_DIR)/grlib-gpl-1.3.7-b4144/designs/leon3-xilinx-ml605/ work/ \
		> $(patsubst update-%,%,$@) ; true

# Cleans all grlib and rvex compilation intermediate files.
.PHONY: weak-clean
weak-clean:
	-$(CHAIN) distclean scripts-clean migclean
	rm -f work/*_beh.prj
	rm -f work/xilinx.log
	rm -f work/timing.twr
	rm -f work/sim-init
	rm -rf work/rvex-lib
	rm -rf work/archive
	rm -f synth.patch

# Removes the entire working directory; use with care (because the work dir might contain
# source files as well, which may not have been put in the patch file yet).
.PHONY: clean
clean: weak-clean
	rm -Irf work
	rm archive-manifest

# Chain to the grlib makefile.
gr-%: work
	@$(CHAIN) $(patsubst gr-%,%,$@)

# Compiles all VHDL files for modelsim to initialize simulation. This must be re-run when
# any VHDL code is changed.
work/sim-init: config.vhd
	$(ARCHIVE_TOOLS)/gen_platform_version_pkg.py $(ARCHIVE_DIR)
	$(WITH_ISE) $(WITH_SIM) $(CHAIN) \
		mig39\
		install-secureip\
		compile_xilinx_verilog_lib\
		compile.vsim\
		vsim\
		map_xilinx_verilog_lib
	touch work/sim-init

# Chain to the compilation makefiles to get the memory srec file.
.PHONY: compile
compile: work
	cd ../compile && $(MAKE)
	cp -f ../compile/ram.srec work/ram.srec

# Simulates using modelsim.
.PHONY: sim
sim: work compile archive-manifest work/sim-init
	$(ARCHIVE_TOOLS)/gen_platform_version_pkg.py $(ARCHIVE_DIR)
	$(WITH_ISE) $(WITH_SIM) $(CHAIN) \
		vsim-launch

# Runs synthesis. This also archives the core when it finishes generating.
.PHONY: synth
synth: work archive-manifest
	
	# Version management.
	$(MAKE) update-synth.patch
	$(ARCHIVE_TOOLS)/archive_platform_prepare.py $(ARCHIVE_DIR)
	rm -f synth.patch
	
	# Something was throwing this away...
	ln -s /home/user/workspace/rvex-rewrite/lib work/rvex-lib
	
	# Synthesis.
	$(WITH_ISE) $(CHAIN) mig39 planahead MAP_COST_TABLE=2
	
	# Gather the log files.
	touch work/xilinx.log
	cat work/planahead/leon3-*/*.runs/synth_1/runme.log >> work/xilinx.log
	cat work/planahead/leon3-*/*.runs/impl_1/runme.log >> work/xilinx.log
	touch work/timing.twr
	-cat work/planahead/leon3-*/*.runs/impl_1/*.twr > work/timing.twr
	
	# Archive the core.
	$(ARCHIVE_TOOLS)/archive_platform_complete.py $(ARCHIVE_DIR)
	
	# Populate the output directory.
	mkdir -p output
	cp work/leon3mp.bit output/fpga.bit
	cp work/xilinx.log output/xilinx.log
	cp work/timing.twr output/timing.twr
	
	# Populate the results directory.
	mkdir -p $(RESULTS_DIR)
	python3 $(SCRIPTS_DIR)/gather_synth_results.py work/xilinx.log work/timing.log $(RESULTS_DIR)
	

# Shorthand for launching ISE.
ise: work
	$(WITH_ISE) $(CHAIN) \
		mig39\
		ise-launch
