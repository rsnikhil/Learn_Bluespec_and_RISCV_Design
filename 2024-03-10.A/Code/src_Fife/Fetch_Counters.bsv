// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Authors: Rishiyur S. Nikhil, ...

package Fetch_Counters;

// ****************************************************************
// Counters associated with Fetch: inum, PC, epoch

// This module is not used in the default pedagogic version of the
// Fetch stage, where inum, pc and epoch are implemented with ordinary
// registers.

// This module illustrates how to re-implements inum, pc and epoch
// with "Concurrent Registers".  This eliminates one cycle of delay
// when the Fetch stage is redirected to a new pc by the Retire stage,
// by "bypassing" the redirection values into the Fetch rule.

// ****************************************************************
// Imports from bsc libraries

// None

// ----------------
// Local imports

// ****************************************************************

interface Fetch_Counters_IFC #(type xlen, type w_epoch);
   interface Reg #(Bit #(64))      inum0;
   interface Reg #(Bit #(64))      inum1;

   interface Reg #(Bit #(xlen))    pc0;
   interface Reg #(Bit #(xlen))    pc1;

   interface Reg #(Bit #(w_epoch)) epoch0;
   interface Reg #(Bit #(w_epoch)) epoch1;
endinterface

// ****************************************************************
// Implementation module using ordinary registers

module mkFetch_Counters (Fetch_Counters_IFC #(xlen, w_epoch));

   Reg #(Bit #(64))       rg_inum  <- mkReg (0);
   Reg #(Bit #(xlen))     rg_pc    <- mkReg (0);
   Reg #(Bit #(w_epoch))  rg_epoch <- mkReg (0);

   // ================================================================
   // INTERFACE

   interface inum0  = rg_inum;
   interface inum1  = rg_inum;

   interface pc0    = rg_pc;
   interface pc1    = rg_pc;

   interface epoch0 = rg_epoch;
   interface epoch1 = rg_epoch;
endmodule

// ****************************************************************
// Implementation module using concurrent registers (CRegs)

module mkFetch_Counters_2 (Fetch_Counters_IFC #(xlen, w_epoch));

   Array #(Reg #(Bit #(64)))       crg_inum  <- mkCReg (2, 0);
   Array #(Reg #(Bit #(xlen)))     crg_pc    <- mkCReg (2, 0);
   Array #(Reg #(Bit #(w_epoch)))  crg_epoch <- mkCReg (2, 0);

   // ================================================================
   // INTERFACE

   interface inum0  = crg_inum [0];
   interface inum1  = crg_inum [1];

   interface pc0    = crg_pc [0];
   interface pc1    = crg_pc [1];

   interface epoch0 = crg_epoch [0];
   interface epoch1 = crg_epoch [1];
endmodule

// ****************************************************************

endpackage
