
.PHONY: help
help:
	@echo ""
	@echo " Makefile script used to automate programming FPGAs using impact. Targets:"
	@echo ""
	@echo "   make prog-ml605-<file.bit>   uploads bitstream to ML605."
	@echo "   make clean                   removes temporary files."
	@echo ""

# Uploads a bitstream to an ML605 development board.
.PHONY: prog-ml605-%
prog-ml605-%: %
	echo "setMode -bs" > impact.cmd
	echo "setCable -port auto" >> impact.cmd
	echo "Identify -inferir" >> impact.cmd
	echo "identifyMPM" >> impact.cmd
	echo "assignFile -p 2 -file $<" >> impact.cmd
	echo "Program -p 2" >> impact.cmd
	echo "quit" >> impact.cmd
	impact -batch impact.cmd
	rm -f impact.cmd

# Cleans temporary files.
.PHONY: clean
clean:
	rm -f impact.cmd
