CORES = $(shell echo core*)

.PHONY: all
all: reset $(patsubst %,%-append,$(CORES))

.PHONY: reset
reset:
	rm -f ram.srec
	touch ram.srec

.PHONY: core%-append
core%-append: core%
	cd $< && $(MAKE) all
	cat $</out.srec >> ram.srec

.PHONY: clean
clean: $(patsubst %,%-clean,$(CORES))
	rm -f ram.srec

.PHONY: core%-clean
core%-clean: core%
	cd $< && $(MAKE) clean

SUFFIXES:

