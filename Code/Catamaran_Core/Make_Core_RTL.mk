###  -*-Makefile-*-
# Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved
# Author: Rishiyur S. Nikhil

$(info INFO: 'make help' shows available targets and current settings.)

# This repo
CATAMARAN_FIFEDRUM_HW ?= ..

# ================================================================
.PHONY: help
help:
	@echo "Targets:"
	@echo "  help (default)  Show this help info"
	@echo "  all/gen_RTL     generate RTL (using bsc; for AWSF1 FPGA or simulation)"
	@echo "  clean           Remove intermediate files"
	@echo "  full_clean      Restore this dir to pristine state"
	@echo ""
	@echo "Local vars:"
	@echo "  PLATFORM_TARGET = $(PLATFORM_TARGET)"
	@echo "                    (affects clock-selection in Catamaran_Core)"
	@echo "  BSC_PATH  = $(BSC_PATH)"
	@echo ""
	@echo "  BSC_FLAGS = $(BSC_FLAGS)"

# ================================================================
# Target platform (affects clock-selection in Catamaran_Core)

PLATFORM_TARGET ?= PLATFORM_AWSF1

# ================================================================
# Convenience

.PHONY: all
all: gen_RTL

# ****************************************************************
# ****************************************************************
# ****************************************************************
# SECTION: Generate Core_RTL

# ----------------
# bsc compiler flags for this project sources

BSC_FLAGS += -D RV32
BSC_FLAGS += -D FABRIC64
BSC_FLAGS += -D WATCH_TOHOST

BSC_FLAGS += -D $(PLATFORM_TARGET)

# Debugging and tracing
# BSC_FLAGS += -D INCLUDE_GDB_CONTROL
# BSC_FLAGS += -D INCLUDE_PC_TRACE
# BSC_FLAGS += -D INCLUDE_TANDEM_VERIF

# bsc generic compiler flags
BSC_FLAGS += -keep-fires -aggressive-conditions -no-warn-action-shadowing
BSC_FLAGS += -no-show-timestamps -check-assert  -show-range-conflict
BSC_FLAGS += -suppress-warnings G0020
BSC_FLAGS += +RTS -K128M -RTS

# ----------------
# Search path for bsc to find .bsv files

BSC_PATH := $(CATAMARAN_FIFEDRUM_HW)/src_Common
BSC_PATH := $(BSC_PATH):$(CATAMARAN_FIFEDRUM_HW)/src_Drum
BSC_PATH := $(BSC_PATH):$(CATAMARAN_FIFEDRUM_HW)/Catamaran_Core/src_BSV

# 'vendored-in' IP
BSC_PATH := $(BSC_PATH):$(CATAMARAN_FIFEDRUM_HW)/vendor/bluespec_Flute
BSC_PATH := $(BSC_PATH):$(CATAMARAN_FIFEDRUM_HW)/vendor/bluespec_AMBA_Fabrics
BSC_PATH := $(BSC_PATH):$(CATAMARAN_FIFEDRUM_HW)/vendor/bluespec_BSV_Additional_Libs
BSC_PATH := $(BSC_PATH):$(CATAMARAN_FIFEDRUM_HW)/vendor/bluespec_RISCV_Debug_Module

# bsc standard libs
BSC_PATH := $(BSC_PATH):+

# ----------------
# Compile Core BSV to RTL

# Top-level BSV file
TOPFILE_CORE = $(CATAMARAN_FIFEDRUM_HW)/Catamaran_Core/src_BSV/AWSteria_Core.bsv

TMP_BSC_CORE  = tmp_bsc_core
TMP_DIRS_CORE = -vdir $(CORE_RTL)  -bdir $(TMP_BSC_CORE)  -info-dir $(TMP_BSC_CORE)

# RTL generated into this dir
CORE_RTL = RTL_Catamaran_Core

.PHONY: gen_RTL
gen_RTL:
	mkdir -p  $(TMP_BSC_CORE)
	mkdir -p  $(CORE_RTL)
	@echo  "INFO: Generating Core RTL in $(CORE_RTL)/ ..."
	bsc -u -elab -verilog  $(TMP_DIRS_CORE) \
		$(BSC_FLAGS) \
		-p $(BSC_PATH) \
		$(TOPFILE_CORE)
	@echo  "INFO: Generated Core RTL in $(CORE_RTL)/"

# ****************************************************************
# ****************************************************************
# ****************************************************************

.PHONY: clean
clean:
	rm -r -f  *~  tmp_*

.PHONY: full_clean
full_clean: clean
	rm -r -f  $(CORE_RTL)

# ================================================================
