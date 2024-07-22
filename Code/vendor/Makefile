.PHONY: help
help:
	@echo "Targets:"
	@echo "  $(TARGETS)"
	@echo "  all           All targets"
	@echo "  clean         Delete temporary files"
	@echo "  full_clean    Restore to pristine state"
	@echo "See each <target>.vendor.hjson for details of remote repos etc."

.PHONY: all
all: $(TARGETS)

# ================================================================
VENDOR_PY = ../Tools/vendor.py

TARGETS += bluespec_BSV_Additional_Libs
LOCKS   += bluespec_BSV_Additional_Libs.lock.hjson
.PHONY: bluespec_BSV_Additional_Libs
bluespec_BSV_Additional_Libs:
	$(VENDOR_PY)  bluespec_BSV_Additional_Libs.vendor.hjson

TARGETS += bluespec_AMBA_Fabrics
LOCKS   += bluespec_AMBA_Fabrics.lock.hjson
.PHONY: bluespec_AMBA_Fabrics
bluespec_AMBA_Fabrics:
	$(VENDOR_PY)  bluespec_AMBA_Fabrics.vendor.hjson

TARGETS += bluespec_Flute
LOCKS   += bluespec_Flute.lock.hjson
.PHONY: bluespec_Flute
bluespec_Flute:
	$(VENDOR_PY)  bluespec_Flute.vendor.hjson

TARGETS += bluespec_RISCV_Debug_Module
LOCKS   += bluespec_RISCV_Debug_Module.lock.hjson
.PHONY: bluespec_RISCV_Debug_Module
bluespec_RISCV_Debug_Module:
	$(VENDOR_PY)  bluespec_RISCV_Debug_Module.vendor.hjson

# ================================================================

.PHONY: clean
clean:
	rm -r -f  *~

.PHONY: full_clean
full_clean: clean
	rm -r -f  $(TARGETS)  $(LOCKS)
