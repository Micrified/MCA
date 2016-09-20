
all: routed.bit

# Defines FPGA to use.
ifndef PART
PART = xc6vlx240t-ff1156-1
endif

# Creates a .prj file for XST from the contents of the vhdl directory.
#project.prj: vhdl
#	find vhdl | grep -E '(^vhdl\/([^\/]+)\/.*\.vhd$$)' | sed -r 's/(^vhdl\/([^\/]+)\/.*\.vhd$$)/vhdl \2 "\1"/g' > project.prj

# Runs synthesis (XST).
synthesized.ngc: project.prj
	echo 'set -tmpdir "xst-tmpdir"' > synthesized.xst
	mkdir -p xst-tmpdir
	
	echo 'set -xsthdpdir "xst-xsthdpdir"' >> synthesized.xst
	mkdir -p xst-xsthdpdir
	
	echo 'run' >> synthesized.xst
	echo '-ifn project.prj' >> synthesized.xst
	echo '-ofn synthesized' >> synthesized.xst
	echo '-ofmt NGC' >> synthesized.xst
	cat opts-xst.cfg >> synthesized.xst
	xst -ifn synthesized.xst

# Runs ngdbuild.
synthesized.ngd: synthesized.ngc constraints.ucf
	ngdbuild -p $(PART) -uc constraints.ucf synthesized.ngc synthesized.ngd

# Runs placer (map).
mapped.ncd constraints.pcf: synthesized.ngd
	map -p $(PART) -w $(shell cat opts-map.cfg) -o mapped.ncd synthesized.ngd constraints.pcf

# Runs router (par).
routed.ncd: mapped.ncd constraints.pcf
	par -w $(shell cat opts-par.cfg) mapped.ncd routed.ncd constraints.pcf

# Creates timing report (trce).
timing.twr: routed.ncd constraints.pcf
	trce -intstyle ise -o timing.twr -v 30 -l 30 routed.ncd constraints.pcf

# Creates bitstream (bitgen).
routed.bit: routed.ncd constraints.pcf
	bitgen routed.ncd routed.bit constraints.pcf

