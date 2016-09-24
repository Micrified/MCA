
RVEX_REWRITE = /home/user/workspace/rvex-rewrite
PLATFORM = $(RVEX_REWRITE)/platform/ml605-grlib-bare
ARCHIVE_TOOLS = $(RVEX_REWRITE)/versions/tools
ARCHIVE_DIR = work/archive
GRLIB_DIR = $(RVEX_REWRITE)/grlib
CHAIN = cd work && $(MAKE) GRLIB=$(GRLIB_DIR)/grlib-gpl-1.3.7-b4144

WITH_ISE = source /home/user/workspace/tools/scripts/sx &&
WITH_SIM = source /home/user/workspace/tools/scripts/sm &&

.PHONY: all
all: synth

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
		rm config.vhd; \
		cp ../config.vhd config.vhd; \
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

# Shorthand notations for simulating, as descibed in the grlib leon project
# readme. THIS DOES A LOT OF EXTRA WORK BECAUSE IT STARTS FROM SCRATCH. FIXME!
.PHONY: sim-%
sim-%: work compile-% archive-manifest
	$(ARCHIVE_TOOLS)/gen_platform_version_pkg.py $(ARCHIVE_DIR)
	$(WITH_ISE) $(WITH_SIM) $(CHAIN) \
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
resim-%: work compile-% archive-manifest
	$(ARCHIVE_TOOLS)/gen_platform_version_pkg.py $(ARCHIVE_DIR)
	$(WITH_ISE) $(WITH_SIM) $(CHAIN) \
		vsim\
		map_xilinx_verilog_lib\
		vsim-launch

# Runs synthesis. This also archives the core when it finishes generating.
.PHONY: synth
synth: work archive-manifest
	
	# Version management.
	$(MAKE) update-synth.patch
	$(ARCHIVE_TOOLS)/archive_platform_prepare.py $(ARCHIVE_DIR)
	rm -f synth.patch
	
	# Synthesis.
	$(WITH_ISE) $(CHAIN) mig39 planahead MAP_COST_TABLE=$(MAP_COST_TABLE)
	
	# More version management.
	touch work/xilinx.log
	cat work/planahead/leon3-*/*.runs/synth_1/runme.log >> work/xilinx.log
	cat work/planahead/leon3-*/*.runs/impl_1/runme.log >> work/xilinx.log
	cat work/planahead/leon3-*/*.runs/impl_1/*.twr > work/timing.twr
	$(ARCHIVE_TOOLS)/archive_platform_complete.py $(ARCHIVE_DIR)

# Shorthand for launching ISE.
ise: work
	$(WITH_ISE) $(CHAIN) \
		scripts-clean\
		migclean\
		mig39\
		ise-launch
