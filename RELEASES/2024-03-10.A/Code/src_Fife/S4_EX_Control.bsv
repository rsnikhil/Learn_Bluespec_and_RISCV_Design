// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package S4_EX_Control;

// ****************************************************************
// Execution pipeline for Control instrs (BRANCH, JAL, JALR)

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
import Inter_Stage :: *;

import Fn_EX_Control :: *;

// ****************************************************************

interface EX_Control_IFC;
   method Action init (Initial_Params initial_params);

   // Forward in
   interface FIFOF_I #(RR_to_EX_Control)     fi_RR_to_EX_Control;
   // Forward out
   interface FIFOF_O #(EX_Control_to_Retire) fo_EX_Control_to_Retire;
endinterface

// ****************************************************************

(* synthesize *)
module mkEX_Control (EX_Control_IFC);
   Reg #(File) rg_flog <- mkReg (InvalidFile);    // debugging

   // Forward in
   FIFOF #(RR_to_EX_Control)      f_RR_to_EX_Control     <- mkPipelineFIFOF;
   // Forward out
   FIFOF #(EX_Control_to_Retire)  f_EX_Control_to_Retire <- mkBypassFIFOF;

   // ================================================================
   // BEHAVIOR

   rule rl_EX_Control;
      let x <- pop_o (to_FIFOF_O (f_RR_to_EX_Control));
      let y <- fn_EX_Control (x, rg_flog);
      f_EX_Control_to_Retire.enq (y);

      wr_log (rg_flog, $format ("CPU.rl_EX_Control"));
      wr_log_cont (rg_flog, $format ("    ", fshow_RR_to_EX_Control (x)));
      wr_log_cont (rg_flog, $format ("    ", fshow_EX_Control_to_Retire (y)));
      ftrace (rg_flog, x.inum, x.pc, x.instr, "EX.C", $format (""));
   endrule

   // ================================================================
   // INTERFACE

   method Action init (Initial_Params initial_params);
      rg_flog <= initial_params.flog;
   endmethod

   // Forward in
   interface fi_RR_to_EX_Control     = to_FIFOF_I (f_RR_to_EX_Control);
   // Forward out
   interface fo_EX_Control_to_Retire = to_FIFOF_O (f_EX_Control_to_Retire);
endmodule

// ****************************************************************

endpackage
