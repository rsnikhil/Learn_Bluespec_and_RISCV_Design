.PHONY: help
help:
	@echo "Targets:"
	@echo "  $(TARGETS)"
	@echo "  all           All targets"
	@echo "  clean         Delete temporary files"
	@echo "  full_clean    Restore to pristine state"
	@echo "See each <target>.vendor.hjson for details of remote repos etc."

# ================================================================
VENDOR_PY = ../Tools/vendor.py

TARGETS += bluespec_BSV_Additional_Libs
LOCKS   += bluespec_BSV_Additional_Libs.lock.hjson
.PHONY: bluespec_BSV_Additional_Libs
bluespec_BSV_Additional_Libs:
	$(VENDOR_PY)  bluespec_BSV_Additional_Libs.vendor.hjson

# ================================================================

.PHONY: all
all: $(TARGETS)

.PHONY: clean
clean:
	rm -r -f  *~

.PHONY: full_clean
full_clean: clean
	rm -r -f  bluespec_BSV_Additional_Libs  bluespec_BSV_Additional_Libs.lock.hjson
