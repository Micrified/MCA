CORES = $(shell echo core*)

.PHONY: all
all:
	rm -f ram.srec
	echo "S00B00006F75742E73726563C1" > ram.srec
	$(MAKE) $(patsubst %,%-append,$(CORES))
	echo "S804000000FB" >> ram.srec
	rvex-objcopy -I srec -O srec ram.srec ram.srec

.PHONY: core%-append
core%-append: core%
	cd $< && $(MAKE) all
	grep "^S[123]" $</out.srec >> ram.srec

.PHONY: clean
clean: $(patsubst %,%-clean,$(CORES))
	rm -f ram.srec

.PHONY: core%-clean
core%-clean: core%
	cd $< && $(MAKE) clean

SUFFIXES:

