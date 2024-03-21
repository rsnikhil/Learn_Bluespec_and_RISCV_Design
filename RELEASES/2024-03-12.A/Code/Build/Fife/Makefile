.PHONY: help
help:
	@echo "Available targets:"
	@echo "  compile       bcs-compile to verilog"
	@echo "  link          verilator-compile-and-link to exe"
	@echo "  run           run exe on test_memhex64, generating fife.log"
	@echo "  show          Show fife.log in spreadsheet"
	@echo "  clean"
	@echo "  full_clean"
	@echo "  all           compile, link, run, show"

.PHONY: all
all: compile link run

# ****************************************************************
# Config

CPU ?= Fife
RV  ?= RV32

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

# Only needed if we import C code
BSC_C_FLAGS += \
	-Xc++  -D_GLIBCXX_USE_CXX11_ABI=0 \
	-Xl -v \
	-Xc -O3 -Xc++ -O3

# ----------------
# bsc's directory search path

BSCPATH = $(SRC_TOP):$(SRC_CPU):$(SRC_COMMON):$(BSV_ADDITIONAL_LIBS):+

# ****************************************************************
# GENERATE VERILOG (for iverilog and/or verilator)

VERILOG_RTL_DIR = verilog

BSCDIRS_V = -vdir $(VERILOG_RTL_DIR)  -bdir build_v  -info-dir build_v
BSCPATH_V = $(BSCPATH)

BLUESPECDIR = $(shell echo 'puts $$env(BLUESPECDIR)' | bluetcl)

build_v:
	mkdir -p $@

verilog:
	mkdir -p $@

.PHONY: compile
compile: build_v verilog
	@echo "INFO: Compiling BSV into Verilog ..."
	bsc -u -elab -verilog  $(BSCDIRS_V)  $(BSCFLAGS)  -p $(BSCPATH_V)  $(TOPFILE)
	@echo "INFO: Finished compiling BSV into Verilog"
	@echo "INFO: Copying bsc library Verilog files"
	@echo "      WARNING: may need more files when source BSV has changed."
	cp -p  $(BLUESPECDIR)/Verilog/RegFile.v        $(VERILOG_RTL_DIR)/
	cp -p  $(BLUESPECDIR)/Verilog/FIFO2.v          $(VERILOG_RTL_DIR)/
	cp -p  $(BLUESPECDIR)/Verilog/SizedFIFO.v      $(VERILOG_RTL_DIR)/

# ****************************************************************
# VERILATOR: compile and link

EXE_VERILATOR ?= exe_$(CPU)_$(RV)_Verilator

# Boilerplate
VERILATOR_RESOURCES_DIR = $(REPO)/Verilator_Resources

# Directory in which Verilator should do its work
VERILATOR_MAKE_DIR = Verilator_Make

VERILATOR_FLAGS += -Wno-COMBDLY
VERILATOR_FLAGS += -Wno-TIMESCALEMOD

# Tell Verilator to ignore '#delay' statements in the RTL
VERILATOR_FLAGS += --no-timing

# Verilator manual recommends these for best performance
#     -O3                          Verilator optimization level
#     --x-assign fast              Optimize X value
#     --x-initial fast             Optimize uninitialized value
#     --noassert                   Disable all assertions
VERILATOR_FLAGS += -O3 --x-assign fast --x-initial fast --noassert

# Verilator passes these flags to the  C++ compiler
VERILATOR_FLAGS += -CFLAGS -O3 -CFLAGS -DVL_DEBUG

# Tell Verilator to dump stats on the design, in file {prefix}__stats.txt
VERILATOR_FLAGS += --stats

# Verilator passes these flags to the 'ld' linker
# VERILATOR_FLAGS += -LDFLAGS -static

VERILATOR_FLAGS += -DTOPMODULE=$(TOPMODULE)
VERILATOR_FLAGS += -DTOPMODULE_V=\"$(TOPMODULE).v\"
VERILATOR_FLAGS += -Mdir $(VERILATOR_MAKE_DIR)
VERILATOR_FLAGS += -Wno-BLKANDNBLK    # For Reg logf $fopen, $fdisplay etc.
# VERILATOR_FLAGS += -LDFLAGS -static

.PHONY: link
link:
	@echo "INFO: Linking for Verilator ..."
	@echo "INFO: All Verilog/SystemVerilog source files expected in $(VERILOG_RTL_DIR)/"
	@echo "INFO: Generating sim_main.cpp for TOPMODULE = $(TOPMODULE)"
	sed  's/TOPMODULE/mkTop/g' \
		$(VERILATOR_RESOURCES_DIR)/sim_main_template.cpp \
		> $(VERILATOR_RESOURCES_DIR)/sim_main.cpp
	@echo "INFO: Verilating Verilog files (in $(VERILATOR_MAKE_DIR))"
	verilator \
		-I$(VERILOG_RTL_DIR) \
		-I$(VERILATOR_RESOURCES_DIR) \
		$(VERILATOR_FLAGS) \
		--cc  --exe --build -j 4 -o $(EXE_VERILATOR)  verilator_wrapper.v \
		--top-module $(TOPMODULE) \
		$(VERILATOR_RESOURCES_DIR)/sim_main.cpp \
		$(SRC_TOP)/C_Mems_Devices.c \
		$(SRC_TOP)/UART_model.c
	mv  $(VERILATOR_MAKE_DIR)/$(EXE_VERILATOR)  .
	@echo "INFO: Finished linking for Verilator"

# ****************************************************************

.PHONY: run
run:
	@echo "INFO: Verilator Simulation ..."
	./$(EXE_VERILATOR) +log
	@echo "INFO: Finished Verilator Simulation"

.PHONY: run_add
run_add:
	@echo "INFO: Verilator Simulation ..."
	ln -s -f ../../Tools/rv32ui-p-add_Example_Code/rv32ui-p-add.memhex32 \
		test.memhex32
	./$(EXE_VERILATOR) +log
	@echo "INFO: Finished Verilator Simulation"

.PHONY: run_hello
run_hello:
	@echo "INFO: Verilator Simulation ..."
	ln -s -f ../../Tools/Hello_World_Example_Code/hello.RV32.bare.memhex32 \
		test.memhex32
	./$(EXE_VERILATOR) +log
	@echo "INFO: Finished Verilator Simulation"

# ****************************************************************

.PHONY: show
show:
	head -1000 log.txt > foo.log
	$(REPO)/Tools/Log_to_CSV/Log_to_CSV.py  foo.log
	open foo.log.csv

# ****************************************************************

.PHONY: clean
clean:
	rm -r -f  *~  .*~  src_*/*~  build*  $(VERILATOR_MAKE_DIR)

.PHONY: full_clean
full_clean: clean
	rm -r -f  exe_*  verilog  fife.log*  log_*

# ****************************************************************
