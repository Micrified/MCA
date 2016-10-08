
.PHONY: help
help:
	@echo ""
	@echo "Assignment 2 commands:"
	@echo ""
	@echo "make compile - compiles your workload. make sim and make run do this for"
	@echo "               you automatically as well."
	@echo ""
	@echo "make sim     - simulates the FPGA platform with the current source code"
	@echo "               in modelsim. Generates performance results including cache"
	@echo "               behavior, though with a simplified memory latency model."
	@echo ""
	@echo "make synth   - synthesizes the design. Generates area utilization info"
	@echo "               and allows testing your design on the boardserver."
	@echo ""
	@echo "make run     - sends the design to the boardserver to measure performance."
	@echo "               If you haven't synthesized yet, this will ask you if you"
	@echo "               want to do that first."
	@echo ""
	@echo "make clean   - deletes all intermediate files. If you get weird errors"
	@echo "               from the other commands, running this and then trying again"
	@echo "               is not a bad idea."
	@echo ""
	@echo "make pack    - packs all the files that you need to hand in at the end of"
	@echo "               the assignment into a tgz archive. This will fail and"
	@echo "               report an error if you're missing one or more required"
	@echo "               files."
	@echo ""

.PHONY: compile
compile:
	@cd data/compile && $(MAKE)

.PHONY: sim
sim:
	@cd data/fpga && $(MAKE) sim

.PHONY: synth
synth:
	@cd data/fpga && $(MAKE) synth

.PHONY: run
run:
	@cd data/fpga && $(MAKE) run

.PHONY: clean
clean:
	@cd data/compile && $(MAKE) clean
	@cd data/fpga && $(MAKE) clean

PACK_SOURCES += configuration.rvex
PACK_SOURCES += src/config.compile
PACK_SOURCES += $(shell find src | grep "\.[hc]$$")
PACK_SOURCES += data/output/fpga.bit
PACK_SOURCES += results/area.txt
PACK_SOURCES += results/energy.txt
PACK_SOURCES += results/performance.txt
PACK_SOURCES += results/timing.txt
PACK_SOURCES += results/run1-core*.log
PACK_SOURCES += results/run2-core*.log
PACK_SOURCES += results/run3-core*.log
PACK_SOURCES += results/run1-power.csv
PACK_SOURCES += results/run2-power.csv
PACK_SOURCES += results/run3-power.csv

.PHONY: pack
pack:
	@if tar czf design.tgz $(PACK_SOURCES); then \
		echo "Successfully packed your design to design.tgz."; \
	else \
		rm design.tgz; \
		echo -e "\e[1;31mFailed to pack design because some files are missing. See above.\e[0m"; \
		false; \
	fi

