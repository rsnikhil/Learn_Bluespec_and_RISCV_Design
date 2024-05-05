help:
	@echo "Targets:"
	@echo "  b_all = b_compile  b_link  b_sim    (for Bluesim)"
	@echo "  v_all = v_compile  v_link  v_sim    (for Verilog & Verilator simulation)"
	@echo ""
	@echo "  clean         Delete intermediate files and dirs"
	@echo "  full_clean    Restore to pristine state"

b_all:	 b_compile  b_link  b_sim
v_all:	 v_compile  v_link  v_sim

# ****************************************************************

TOPFILE   ?= src_BSV/Top.bsv
TOPMODULE ?= mkTop

BSCFLAGS = -D RV32 -use-dpi -keep-fires  -elab

# Other flags of interest
#	-opt-undetermined-vals \
#	-unspecified-to X \
#	-show-range-conflict \
#	-aggressive-conditions \
#	-no-warn-action-shadowing \
#	-no-inline-rwire \


# C sources for C functions called from BSV using 'import BDPI'
C_FILES =

# Flags passed to the C compiler when linking in C_FILES
BSC_C_FLAGS += \
	-Xc++  -D_GLIBCXX_USE_CXX11_ABI=0 \
	-Xl -v \
	-Xc -O3 -Xc++ -O3

# Common BSC PATH

BSCPATH = src_BSV:+

# ****************************************************************
# FOR BLUESIM

# Final simulation executable
EXEFILE_BSIM ?= exe_HW_bsim

BSCDIRS_BSIM  = -simdir build_bsim -bdir build -info-dir build
BSCPATH_BSIM  = $(BSCPATH)

build_bsim:
	mkdir -p $@

build:
	mkdir -p $@

.PHONY: b_compile
b_compile: build_bsim build
	@echo "Compiling for Bluesim ..."
	bsc -u -sim $(BSCDIRS_BSIM)  $(BSCFLAGS)  -p $(BSCPATH_BSIM)  $(TOPFILE)
	@echo "Compiled for Bluesim"

.PHONY: b_link
b_link:
	@echo "Linking for Bluesim ..."
	bsc  -sim  $(BSCDIRS_BSIM)  -p $(BSCPATH_BSIM) \
		-e $(TOPMODULE) -o ./$(EXEFILE_BSIM) \
		$(BSC_C_FLAGS) $(C_FILES)
	@echo "Linked for Bluesim"

.PHONY: b_sim
b_sim:
	@echo "Simulating in Bluesim ..."
	./$(EXEFILE_BSIM)
	@echo "Simulated in Bluesim"

# ****************************************************************
# FOR Verilator

# Final simulation executable
EXEFILE_VSIM ?= exe_HW_vsim

BSCDIRS_VSIM = -bdir build_v  -info-dir build_v  -vdir verilog
BSCPATH_VSIM = $(BSCPATH)

build_v:
	mkdir -p $@

verilog:
	mkdir -p $@

.PHONY: v_compile
v_compile: build_v verilog
	@echo "Compiling to Verilog ..."
	bsc -u -verilog  $(BSCDIRS_VSIM)  $(BSCFLAGS)  -p $(BSCPATH_VSIM)  $(TOPFILE)
	@echo "Compiled to Verilog"

.PHONY: v_link
v_link:
	@echo "Linking Verilog for Verilator simulation ..."
	bsc -verilog  -vsim verilator  -use-dpi  $(BSCDIRS_VSIM) \
		-e $(TOPMODULE) -o ./$(EXEFILE_VSIM) \
		$(BSC_C_FLAGS) $(C_FILES)
	@echo "Linked Verilog for Verilator simulation: $(EXEFILE_VSIM)"

.PHONY: v_sim
v_sim:
	@echo "Simulating Verilog in Verilator ..."
	./$(EXEFILE_VSIM)
	@echo "Simulated Verilog in Verilator ..."

# ****************************************************************

.PHONY: clean
clean:
	rm -r -f  *~   src_BSV/*~  build*

.PHONY: full_clean
full_clean: clean
	rm -r -f  exe_*  verilog

# ****************************************************************
