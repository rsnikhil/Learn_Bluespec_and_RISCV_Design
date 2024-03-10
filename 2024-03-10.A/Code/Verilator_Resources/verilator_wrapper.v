// Copyright (c) 2018-2021 Rishiyur Nikhil and Bluespec, Inc.

// Flags for verilator

`verilator_config
lint_off -rule WIDTH
lint_off -rule CASEINCOMPLETE
lint_off -rule STMTDLY
lint_off -rule INITIALDLY
lint_off -rule UNSIGNED
lint_off -rule CMPCONST
lint_off -rule MULTIDRIVEN
`verilog

`include `TOPMODULE_V
