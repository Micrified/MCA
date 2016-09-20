
.PHONY: help patch-%

help:
	@echo ""
	@echo " This makefile will assist in downloading grlib and patching it where"
	@echo " necessary. If the download fails or the link breaks, you can also"
	@echo " manually download grlib-gpl-<version>.tar.gz and place it in this"
	@echo " folder manually."
	@echo ""
	@echo " Targets:"
	@echo ""
	@echo " make grlib-gpl-<version> : downloads, extracts and patches grlib."
	@echo " make patch-<version>     : updates the patch file."

# Attempts to download grlib if it doesn't exist.
grlib-gpl-%.tar.gz:
	wget http://ftp.tudelft.nl/TUDelft/rvex/grlib/$@

# Extracts and patches grlib.
grlib-gpl-%: patch-%.patch
	$(MAKE) $@.tar.gz
	tar -xzf $@.tar.gz
	cd $@ && patch -p1 < ../patch-$(patsubst grlib-gpl-%,%,$@).patch ; true
	touch $@

# Updates the patchfile.
patch-%:
	$(MAKE) grlib-gpl-$*.tar.gz
	mkdir clean
	cd clean && tar -xzf ../$(patsubst patch-%,grlib-gpl-%,$@).tar.gz
	diff -rupN\
	  --exclude 'tech'\
	  clean/$(patsubst patch-%,grlib-gpl-%,$@)/\
	  $(patsubst patch-%,grlib-gpl-%,$@)/\
	  > $@.patch ; true
	rm -rf clean

# Removes all downloaded content.
clean:
	rm -rf grlib-*
