# WARNING: This Makefile is 'include'd from other Makefiles. It should not be used by itself.

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  b_compile b_link         bsc-compile and link for Bluesim"
	@echo "  v_compile v_link         bsc-compile and link for Verilator"
	@echo ""
	@echo "  b_run      /v_run        run exe on test_memhex64, generating log.txt"
	@echo "  b_run_hello/v_run_hello  ... on 'Hello World!' test"
	@echo "  b_run_add  /v_run_add    ... on 'add' ISA test"
	@echo ""
	@echo "  b_all = b_compile b_link b_run_hello"
	@echo "  v_all = v_compile v_link v_run_hello"
	@echo ""
	@echo "  csv                      Create CSV file from log.txt for pipeline visualization."
	@echo "                           Then, load the CSV file into any spreadsheet"
	@echo "                           such as: Excel, Numbers, OpenOffice, ...)"
	@echo ""
	@echo "  clean                    Remove temporary intermediate files"
	@echo "  full_clean               Restore to pristine state"

.PHONY: all
b_all: b_compile b_link b_run_hello
v_all: v_compile v_link v_run_hello

# ****************************************************************
# Config

EXEFILE ?= exe_$(CPU)_$(RV)

# ****************************************************************
# Common bsc args

REPO = ../..

SRC_CPU    = $(REPO)/src_$(CPU)
SRC_TOP    = $(REPO)/src_Top
SRC_COMMON = $(REPO)/src_Common

TOPFILE   ?= $(SRC_TOP)/Top.bsv
TOPMODULE ?= mkTop

BSV_ADDITIONAL_LIBS = $(REPO)/vendor/bluespec_BSV_Additional_Libs

BSCFLAGS = -D $(RV) \
	-use-dpi \
	-keep-fires \
	-aggressive-conditions \
	-no-warn-action-shadowing \
	-show-range-conflict \
        -opt-undetermined-vals \
	-unspecified-to X \
	-show-schedule

C_FILES  = $(REPO)/src_Top/C_Mems_Devices.c
C_FILES += $(REPO)/src_Top/UART_model.c

# Only needed if we import C code
BSC_C_FLAGS += -Xl -v  -Xc -O3  -Xc++ -O3

ifdef DRUM_RULES
BSCFLAGS += -D DRUM_RULES
endif

# ----------------
# bsc's directory search path

BSCPATH = $(SRC_TOP):$(SRC_CPU):$(SRC_COMMON):$(BSV_ADDITIONAL_LIBS):+

# ****************************************************************
# FOR VERILATOR

VSIM      = verilator

BSCDIRS_V = -bdir build_v  -info-dir build_v  -vdir verilog

BSCPATH_V = $(BSCPATH)

build_v:
	mkdir -p $@

verilog:
	mkdir -p $@

.PHONY: v_compile
v_compile: build_v verilog
	@echo "Compiling for Verilog (Verilog generation) ..."
	bsc -u -elab -verilog  $(BSCDIRS_V)  $(BSCFLAGS)  -p $(BSCPATH_V)  $(TOPFILE)
	@echo "Verilog generation finished"

.PHONY: v_link
v_link: build_v verilog
	@echo "Linking for Verilog simulation (simulator: $(VSIM)) ..."
	bsc -verilog  -vsim $(VSIM)  -use-dpi  -keep-fires  -v  $(BSCDIRS_V) \
		-e $(TOPMODULE) -o ./$(EXEFILE)_$(VSIM) \
		$(BSC_C_FLAGS) \
		$(C_FILES)
	@echo "Linking for Verilog simulation finished"

# ----------------
# Verilator runs

.PHONY: v_run
v_run:
	@echo "INFO: Simulation ..."
	./$(EXEFILE)_verilator  +log
	@echo "INFO: Finished Simulation"

.PHONY: v_run_hello
v_run_hello:
	@echo "INFO: Simulation of Hello World! ..."
	ln -s -f ../../Tools/Hello_World_Example_Code/hello.RV32.bare.memhex32 \
		test.memhex32
	./$(EXEFILE)_verilator  +log
	@echo "INFO: Finished Simulation of Hello World! ..."

.PHONY: v_run_add
v_run_add:
	@echo "INFO: Simulation of add ISA test ..."
	ln -s -f ../../Tools/rv32ui-p-add_Example_Code/rv32ui-p-add.memhex32 \
		test.memhex32
	./$(EXEFILE)_verilator  +log
	@echo "INFO: Finished Simulation of add ISA test ..."

# ****************************************************************
# FOR BLUESIM

BSCDIRS_BSIM_c = -bdir build_b -info-dir build_b
BSCDIRS_BSIM_l = -simdir C_for_bsim

BSCPATH_BSIM = $(BSCPATH)

build_b:
	mkdir -p $@

C_for_bsim:
	mkdir -p $@

.PHONY: b_compile
b_compile: build_b
	@echo Compiling for Bluesim ...
	bsc -u -sim $(BSCDIRS_BSIM_c)  $(BSCFLAGS)  -p $(BSCPATH_BSIM)  $(TOPFILE)
	@echo Compilation for Bluesim finished

.PHONY: b_link
b_link: build_b C_for_bsim
	@echo Linking for Bluesim ...
	bsc  -sim  -parallel-sim-link 8\
		$(BSCDIRS_BSIM_c)  $(BSCDIRS_BSIM_l)  -p $(BSCPATH_BSIM) \
		-e $(TOPMODULE) -o ./$(EXEFILE)_bsim \
		-keep-fires \
		$(BSC_C_FLAGS)  $(C_FILES)
	@echo Linking for Bluesim finished

# ----------------

.PHONY: b_run
b_run:
	@echo "INFO: Simulation ..."
	./$(EXEFILE)_bsim  +log
	@echo "INFO: Finished Simulation"

.PHONY: b_run_hello
b_run_hello:
	@echo "INFO: Simulation of Hello World! ..."
	ln -s -f ../../Tools/Hello_World_Example_Code/hello.RV32.bare.memhex32 \
		test.memhex32
	./$(EXEFILE)_bsim  +log
	@echo "INFO: Finished Simulation of Hello World! ..."

.PHONY: b_run_add
b_run_add:
	@echo "INFO: Simulation of add ISA test ..."
	ln -s -f ../../Tools/rv32ui-p-add_Example_Code/rv32ui-p-add.memhex32 \
		test.memhex32
	./$(EXEFILE)_bsim  +log
	@echo "INFO: Finished Simulation of add ISA test ..."

# ****************************************************************
# Create CSV file of first 100 instructions for viewing in any spreadsheet

.PHONY: csv
csv:
	$(REPO)/Tools/Log_to_CSV/Log_to_CSV.py  log.txt  0 100

# ****************************************************************

.PHONY: clean
clean:
	rm -r -f  *~  .*~  src_*/*~  build*  C_for_bsim  $(VERILATOR_MAKE_DIR)

.PHONY: full_clean
full_clean: clean
	rm -r -f  exe_*  verilog  log*  $(REPO)/src_Top/*.o  obj_dir_*

# ****************************************************************
