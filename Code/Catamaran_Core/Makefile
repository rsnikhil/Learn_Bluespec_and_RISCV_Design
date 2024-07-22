###  -*-Makefile-*-
# Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved
# Author: Rishiyur S. Nikhil

$(info INFO: 'make help' shows available targets and current settings.)

# ****************************************************************

.PHONY: help
help:
	@echo "Targets:"
	@echo "  help (default)        Show this help info"
	@echo "  all/$(SIM_EXE_FILE)"
	@echo "                        From RTL, create simulation exe using Verilator"
	@echo ""
	@echo "  clean                 Remove Verilator and other intermediate files"
	@echo "  full_clean            clean; remove $(SIM_EXE_FILE) and $(RTL_CATAMARAN_CORE)"
	@echo ""
	@echo "  Current settings:"
	@echo "    SIM_EXE_FILE            = $(SIM_EXE_FILE)"
	@echo "    RTL_CATAMARAN_CORE      = $(RTL_CATAMARAN_CORE)"
	@echo "    RTL_CATAMARAN_SANS_CORE = $(RTL_CATAMARAN_SANS_CORE)"
	@echo "    VERILATOR_WORKING_DIR   = $(VERILATOR_WORKING_DIR)"

# Final executable file
SIM_EXE_FILE ?= exe_HW_AWSF1_sim

# Directory for Catamaran_Core RTL
RTL_CATAMARAN_CORE = RTL_Catamaran_Core
# Local directory containing Catamaran_sans_Core
# Do not edit!
RTL_CATAMARAN_SANS_CORE = RTL_Catamaran_sans_Core

# Convenience
.PHONY: all
all: $(SIM_EXE_FILE)

# ****************************************************************
# ** VERILATOR FLAGS: EDIT IF NEEDED FOR CATAMARAN CORE's RTL   **
# ** Consult Verilator manual for details about flags           **
# ****************************************************************

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

# Tell Verilator to generate multi-threaded simulation code
#     --threads N                  Use N threads
#     --threads-dpi none/pure/all  Which DPI functions are considered thread-safe
# VERILATOR_FLAGS += --threads 6  --threads-dpi pure
VERILATOR_FLAGS += --threads  1

# Misc. Verilator flags
VERILATOR_FLAGS += --unroll-count  256
# -Wno-PINMISSING 
VERILATOR_FLAGS += -Werror-PINMISSING
VERILATOR_FLAGS += -Werror-IMPLICIT
VERILATOR_FLAGS += -Wno-fatal
VERILATOR_FLAGS += -Wno-PINCONNECTEMPTY
VERILATOR_FLAGS += -Wno-ASSIGNDLY
VERILATOR_FLAGS += -Wno-DECLFILENAME
VERILATOR_FLAGS += -Wno-UNUSED
VERILATOR_FLAGS += -Wno-UNOPTFLAT
VERILATOR_FLAGS += -Wno-style

# Tell Verilator to generate VCDs (fix trace-depth according to module hierarchy)
#     --trace  --trace-depth 2  -CFLAGS -DVM_TRACE
# VERILATOR_FLAGS += --trace  -CFLAGS -DVM_TRACE

# ****************************************************************
# ** VERILATOR FILES                                            **
# ****************************************************************

# NOTE: For Verilog and SystemVerilog files that just contain modules
# and module instantiations, Verilator will find them automatically
# using its search path during recursive module instantiation, they do
# not have to be named on the the command line.

# HOWEVER: For SystemVerilog files that contain packages and type
# definitions, these typically must be given on the command-line, and
# often in a particular order (if some packages use other packages).

# For Flute: Catamaran_Core has only Verilog and no SystemVerilog
# files, so no need for any defs here.

# ****************************************************************
# ** VERILATOR DIRECTORIES                                      **
# ****************************************************************

# Directory for Verilator's temporary files etc.
VERILATOR_WORKING_DIR  = Verilator_Working_Dir
VERILATOR_FLAGS += -Mdir $(VERILATOR_WORKING_DIR)

# ****************************************************************
# ** GENERATE VERILATOR SIMULATION EXECUTABLE                   **
# ****************************************************************

# Top-level C++ file (Verilator simulation driver)
VERILATOR_FILES += $(RTL_CATAMARAN_SANS_CORE)/sim_main.cpp

# Top-level Verilog file
TOPMODULE = mkTop_HW_Side
VERILATOR_FILES += $(RTL_CATAMARAN_SANS_CORE)/$(TOPMODULE).v

# C file with DPI-C functions
VERILATOR_FILES += $(RTL_CATAMARAN_SANS_CORE)/C_Imported_Functions.c

# ----------------
# WARNING: This rule depends on prior population of
#     $(RTL_CATAMARAN_CORE)
# and $(RTL_CATAMARAN_SANS_CORE)
# with all RTL, C and C++ files.
# The dependencies of this rule are just two sample files, not a full dependency check.

$(SIM_EXE_FILE): $(RTL_CATAMARAN_SANS_CORE)/mkTop_HW_Side.v \
		 $(RTL_CATAMARAN_CORE)/mkAWSteria_Core.v
	@echo "INFO: Verilating RTL/C/C++ files in $(RTL_CATAMARAN_SANS_CORE)"
	@echo "      and $(RTL_CATAMARAN_CORE)"
	@echo "      using working directory $(VERILATOR_WORKING_DIR)"
	verilator \
		$(VERILATOR_FLAGS) \
		--cc  --exe --build -j 4 \
		--top-module $(TOPMODULE) \
		-I$(RTL_CATAMARAN_SANS_CORE) \
		-I$(RTL_CATAMARAN_CORE) \
		-o $(SIM_EXE_FILE) \
		$(VERILATOR_FILES)
	cp -p  $(VERILATOR_WORKING_DIR)/$(SIM_EXE_FILE)  .
	@echo "----------------"
	@echo "INFO: Created verilator simulation executable:  $(SIM_EXE_FILE)"

# ****************************************************************
# ****************************************************************
# ****************************************************************

.PHONY: clean
clean:
	rm -r -f  *~  $(VERILATOR_WORKING_DIR)  trace_*

.PHONY: full_clean
full_clean: clean
	rm -r -f  $(SIM_EXE_FILE)  $(RTL_CATAMARAN_CORE)

# ==============================================================
