
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

.PHONY: compile
compile:
	@cd data/compile && $(MAKE)

.PHONY: sim
sim:
	@cd data/fpga && $(MAKE) sim

.PHONY: synth
synth:
	@cd data/fpga && $(MAKE) sim

.PHONY: run
run:
	@cd data/fpga && $(MAKE) sim

.PHONY: clean
clean:
	@cd data/compile && $(MAKE) clean
	@cd data/fpga && $(MAKE) clean

