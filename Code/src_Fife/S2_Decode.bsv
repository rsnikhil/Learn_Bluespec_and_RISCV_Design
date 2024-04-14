// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Authors: Rishiyur S. Nikhil, ...

package S2_Decode;

// ****************************************************************
// Decode stage
// * Check that instruction is legal, and note if it uses rs1/rs2/rd

// ****************************************************************
// Imports from bsc libraries

import FIFOF        :: *;
import SpecialFIFOs :: *;    // For mkPipelineFIFOF and mkBypassFIFOF

// ----------------
// Imports from 'vendor' libs

import Cur_Cycle  :: *;
import Semi_FIFOF :: *;

// ----------------
// Local imports

import Utils       :: *;
import Instr_Bits  :: *;
import Mem_Req_Rsp :: *;
import Inter_Stage :: *;

import Fn_Decode   :: *;

// ****************************************************************

interface Decode_IFC;
   method Action init (Initial_Params initial_params);

   // Forward in
   interface FIFOF_I #(Fetch_to_Decode)  fi_Fetch_to_Decode;
   interface FIFOF_I #(Mem_Rsp)          fi_IMem_to_Decode;

   // Forward out
   interface FIFOF_O #(Decode_to_RR)  fo_Decode_to_RR;
endinterface

// ****************************************************************

(* synthesize *)
module mkDecode (Decode_IFC);
   // ================================================================
   // STATE
   Reg #(File) rg_flog <- mkReg (InvalidFile);    // debugging

   // Forward flows in
   // Depth should be > F=>IMem=>D path latency
   FIFOF #(Fetch_to_Decode)  f_Fetch_to_Decode <- mkSizedFIFOF (4);
   FIFOF #(Mem_Rsp)          f_IMem_to_Decode  <- mkPipelineFIFOF;

   // Forward flow out
   FIFOF #(Decode_to_RR) f_Decode_to_RR <- mkBypassFIFOF;

   // ================================================================
   // BEHAVIOR

   rule rl_Decode;
      Fetch_to_Decode  x        <- pop_o (to_FIFOF_O (f_Fetch_to_Decode));
      Mem_Rsp          rsp_IMem <- pop_o (to_FIFOF_O (f_IMem_to_Decode));

      Decode_to_RR y <- fn_Decode (x, rsp_IMem, rg_flog);

      f_Decode_to_RR.enq (y);

      log_Decode (rg_flog, y, rsp_IMem);

   endrule

   // ================================================================
   // INTERFACE

   method Action init (Initial_Params initial_params);
      rg_flog <= initial_params.flog;
   endmethod

   // Forward flows in
   interface fi_Fetch_to_Decode = to_FIFOF_I (f_Fetch_to_Decode);
   interface fi_IMem_to_Decode  = to_FIFOF_I (f_IMem_to_Decode);
   // Forward flows out
   interface fo_Decode_to_RR = to_FIFOF_O (f_Decode_to_RR);
endmodule

// ****************************************************************

endpackage
