// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package S4_EX_Int;

// ****************************************************************
// Execution pipeline for LUI, AUIPC and Integer arith ops (RV32I, RV64I)

// Note: no "M" opcodes (integer multiply/divide); that may become a
// separate pipe, possibly taking more cycles.

// ****************************************************************
// Imports from libraries

import FIFOF        :: *;
import SpecialFIFOs :: *;    // For mkPipelineFIFOF, mkBypassFIFOF

// ----------------
// Imports from 'vendor' libs

import Cur_Cycle :: *;
import Semi_FIFOF :: *;

// ----------------
// Local imports

import Utils       :: *;
import Instr_Bits  :: *;
import CSR_Bits    :: *;    // For trap CAUSE
import IALU        :: *;
import Inter_Stage :: *;

import Fn_EX_Int :: *;

// ****************************************************************

interface EX_Int_IFC;
   method Action init (Initial_Params initial_params);

   // Forward in
   interface FIFOF_I #(RR_to_EX)     fi_RR_to_EX_Int;
   // Forward out
   interface FIFOF_O #(EX_to_Retire) fo_EX_Int_to_Retire;
endinterface

// ****************************************************************

(* synthesize *)
module mkEX_Int (EX_Int_IFC);
   Reg #(File) rg_flog <- mkReg (InvalidFile);    // debugging

   // Forward in
   FIFOF #(RR_to_EX)      f_RR_to_EX_Int     <- mkPipelineFIFOF;
   // Forward out
   FIFOF #(EX_to_Retire)  f_EX_Int_to_Retire <- mkBypassFIFOF;

   // ================================================================
   // BEHAVIOR

   rule rl_EX_Int;
      let x <- pop_o (to_FIFOF_O (f_RR_to_EX_Int));
      let y <- fn_EX_Int (x, rg_flog);
      f_EX_Int_to_Retire.enq (y);

      wr_log (rg_flog, $format ("CPU.rl_EX_Int:"));
      wr_log_cont (rg_flog, $format ("    ", fshow_RR_to_EX (x)));
      wr_log_cont (rg_flog, $format ("    ", fshow_EX_to_Retire (y)));
      ftrace (rg_flog, x.inum, x.pc, x.instr, "EX.I", $format (""));
   endrule

   // ================================================================
   // INTERFACE

   method Action init (Initial_Params initial_params);
      rg_flog <= initial_params.flog;
   endmethod

   // Forward in
   interface fi_RR_to_EX_Int = to_FIFOF_I (f_RR_to_EX_Int);

   // Forward out
   interface fo_EX_Int_to_Retire = to_FIFOF_O (f_EX_Int_to_Retire);
endmodule

// ****************************************************************

endpackage
