// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Arch;

// ****************************************************************
// Arch configs:
//     RV32  RV64
//     ISA_M  ISA_A  ISA_F  ISA_D  ISA_C
//     PRIV_S  PRIV_U

// ****************************************************************


`ifdef RV32

typedef 32 XLEN;

`elsif RV64

typedef 64 XLEN;

`endif

Integer xlen = valueOf (XLEN);

// ****************************************************************

endpackage
