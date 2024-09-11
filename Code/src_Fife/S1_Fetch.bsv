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
// Debugger control

typedef enum { S1_RUNNING, S1_HALTED } S1_RunState
deriving (Bits, Eq, FShow);

Integer verbosity = 0;

// ****************************************************************

(* synthesize *)
module mkFetch (Fetch_IFC);
   // ----------------------------------------------------------------
   // STATE
   Reg #(File) rg_flog    <- mkReg (InvalidFile);    // Debugging

   Reg #(S1_RunState) rg_runstate <- mkReg (S1_HALTED);

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
   rule rl_Fetch_req ((rg_runstate == S1_RUNNING)
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

      // Debugger support
      if (x.haltreq) begin
	 Fetch_to_Decode to_D = unpack (0);
	 to_D.epoch         = rg_epoch;    // old epoch
	 to_D.halt_sentinel = True;
	 f_Fetch_to_Decode.enq (to_D);
	 rg_runstate <= S1_HALTED;
	 if (verbosity != 0)
	    $display ("S1_Fetch: halt requested; sending halt_sentinel to S2_Decode");
      end
      else if (rg_runstate == S1_HALTED) begin
	 rg_runstate <= S1_RUNNING;
	 if (verbosity != 0)
	    $display ("S1_Fetch: resuming at PC %0h epoch %0d", x.next_pc, x.next_epoch);
      end

      // If one-instr-at-a-time, re-enable fetching
      rg_oiaat_fetch <= True;

      log_Redirect (rg_flog, x);
   endrule

   // ----------------------------------------------------------------
   // INTERFACE

   method Action init (Initial_Params initial_params) if (rg_runstate == S1_HALTED);
      rg_flog    <= initial_params.flog;
      rg_pc      <= initial_params.pc_reset_value;
      rg_runstate <= S1_RUNNING;
   endmethod

   // Forward out
   interface fo_Fetch_to_Decode = to_FIFOF_O (f_Fetch_to_Decode);
   interface fo_Fetch_to_IMem   = to_FIFOF_O (f_Fetch_to_IMem);

   // Backward in
   interface fi_Fetch_from_Retire = to_FIFOF_I (f_Fetch_from_Retire);
endmodule

// ****************************************************************

endpackage
