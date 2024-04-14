// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Authors: Rishiyur S. Nikhil, ...

package S1_Fetch;

// ****************************************************************
// Fetch stage, including next-PC predictor

// ****************************************************************
// Imports from bsc libraries

import FIFOF        :: *;
import SpecialFIFOs :: *;

// ----------------
// Imports from 'vendor' libs

import Cur_Cycle  :: *;
import Semi_FIFOF :: *;

// ----------------
// Local imports

import Utils       :: *;
import Arch        :: *;
import Instr_Bits  :: *;
import Mem_Req_Rsp :: *;
import Inter_Stage :: *;

import Fn_Fetch       :: *;

// ****************************************************************

interface Fetch_IFC;
   method Action init (Initial_Params initial_params);

   // Forward out
   interface FIFOF_O #(Fetch_to_Decode)  fo_Fetch_to_Decode;
   interface FIFOF_O #(Mem_Req)          fo_Fetch_to_IMem;

   // Backward in
   interface FIFOF_I #(Fetch_from_Retire) fi_Fetch_from_Retire;
endinterface


// ****************************************************************

(* synthesize *)
module mkFetch (Fetch_IFC);
   // ----------------------------------------------------------------
   // STATE
   Reg #(File) rg_flog    <- mkReg (InvalidFile);    // Debugging
   Reg #(Bool) rg_running <- mkReg (False);

   // Forward out
   FIFOF #(Fetch_to_Decode) f_Fetch_to_Decode <- mkBypassFIFOF;
   FIFOF #(Mem_Req)         f_Fetch_to_IMem   <- mkBypassFIFOF;

   // Backward in
   FIFOF #(Fetch_from_Retire) f_Fetch_from_Retire <- mkPipelineFIFOF;

   // inum, PC and epoch registers
   Reg #(Bit #(64))       rg_inum  <- mkReg (0);
   Reg #(Bit #(XLEN))     rg_pc    <- mkReg (0);
   Reg #(Bit #(W_Epoch))  rg_epoch <- mkReg (0);


   Reg #(Bool) rg_oiaat       <- mkReg (False);
   Reg #(Bool) rg_oiaat_fetch <- mkReg (True);

   // ----------------------------------------------------------------
   // BEHAVIOR

   // Forward flow
   rule rl_Fetch_req (rg_running
		      && (! f_Fetch_from_Retire.notEmpty)
		      && rg_oiaat_fetch);

      // Predict next PC
      let pred_pc = rg_pc + 4;

      let y <- fn_Fetch (rg_pc, pred_pc, rg_epoch, rg_inum, rg_flog);
      f_Fetch_to_Decode.enq (y.to_D);
      f_Fetch_to_IMem.enq (y.mem_req);

      rg_pc   <= pred_pc;
      rg_inum <= rg_inum + 1;

      // If one-instr-at-a-time, disable fetching
      // (will be re-enabled by rl_Fetch_from_Retire)
      if (rg_oiaat) rg_oiaat_fetch <= False;

      log_Fetch (rg_flog, y.to_D, y.mem_req);
   endrule

   // Backward flow: redirection from Retire
   rule rl_Fetch_from_Retire ((! rg_oiaat) || (! rg_oiaat_fetch));
      let x <- pop_o (to_FIFOF_O (f_Fetch_from_Retire));
      rg_pc    <= x.next_pc;
      rg_epoch <= x.next_epoch;

      // If one-instr-at-a-time, re-enable fetching
      rg_oiaat_fetch <= True;

      log_Redirect (rg_flog, x);
   endrule

   // ----------------------------------------------------------------
   // INTERFACE

   method Action init (Initial_Params initial_params) if (! rg_running);
      rg_flog    <= initial_params.flog;
      rg_pc      <= initial_params.pc_reset_value;
      rg_running <= True;
   endmethod

   // Forward out
   interface fo_Fetch_to_Decode = to_FIFOF_O (f_Fetch_to_Decode);
   interface fo_Fetch_to_IMem   = to_FIFOF_O (f_Fetch_to_IMem);

   // Backward in
   interface fi_Fetch_from_Retire = to_FIFOF_I (f_Fetch_from_Retire);
endmodule

// ****************************************************************

endpackage
