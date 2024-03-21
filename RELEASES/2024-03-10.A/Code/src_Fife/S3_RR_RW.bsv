// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package S3_RR_RW;

// ****************************************************************
// Register-read-and-dispatch, and Register-Write
// * Has scoreboard to keep track of which register are "busy"
// * Stalls if rs1, rs2 or rd are busy
// * Reads input register values

// ****************************************************************
// Imports from bsc libraries

import FIFOF        :: *;
import SpecialFIFOs :: *;    // For mkPipelineFIFOF and mkBypassFIFOF
import Vector       :: *;
import Connectable  :: *;

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
import RISCV_GPRs  :: *;

import Fn_Dispatch :: *;
import Fn_EX_DMem  :: *;

// ****************************************************************

interface RR_RW_IFC;
   method Action init (Initial_Params initial_params);

   // Forward in
   interface FIFOF_I #(Decode_to_RR)  fi_Decode_to_RR;

   // Forward out
   interface FIFOF_O #(RR_to_Retire)      fo_RR_to_Retire;
   interface FIFOF_O #(RR_to_EX_Control)  fo_RR_to_EX_Control;
   interface FIFOF_O #(RR_to_EX)          fo_RR_to_EX_Int;
   interface FIFOF_O #(Mem_Req)           fo_DMem_S_req;

   // Backward in
   interface FIFOF_I #(RW_from_Retire)  fi_RW_from_Retire;
endinterface

// ****************************************************************

(* synthesize *)
module mkRR_RW (RR_RW_IFC);
   Reg #(File) rg_flog <- mkReg (InvalidFile);

   // Forward in
   FIFOF #(Decode_to_RR) f_Decode_to_RR <- mkPipelineFIFOF;

   // Forward out
   FIFOF #(RR_to_Retire)     f_RR_to_Retire     <- mkBypassFIFOF;  // Direct
   FIFOF #(RR_to_EX_Control) f_RR_to_EX_Control <- mkBypassFIFOF;
   FIFOF #(RR_to_EX)         f_RR_to_EX_Int     <- mkBypassFIFOF;
   FIFOF #(Mem_Req)          f_DMem_S_req       <- mkBypassFIFOF;

   // Backward in
   FIFOF #(RW_from_Retire) f_RW_from_Retire <- mkPipelineFIFOF;

   // The integer register file (GPRs)
   RISCV_GPRs_IFC #(XLEN)  gprs <- mkRISCV_GPRs_synth;

   // Scoreboard for GPRs
   Reg #(Scoreboard) rg_scoreboard <- mkReg (replicate (0));

   Reg #(Bit #(8)) rg_stall_count <- mkReg (0);

   // ================================================================
   // BEHAVIOR: Forward

   rule rl_RR_Dispatch (! f_RW_from_Retire.notEmpty);
      if (rg_stall_count > 15) begin
	 $fdisplay (rg_flog, "%0d: CPU.rl_RR: reached %0d stalls; quitting",
		    cur_cycle, rg_stall_count);
	 $finish (1);
      end

      let x       = f_Decode_to_RR.first;
      let instr   = x.instr;
      let opclass = x.opclass;
      let rs1     = instr_rs1 (instr);
      let rs2     = instr_rs2 (instr);
      let rd      = instr_rd  (instr);

      let scoreboard = rg_scoreboard;
      let busy_rs1   = (x.has_rs1 && (scoreboard [rs1] != 0));
      let busy_rs2   = (x.has_rs2 && (scoreboard [rs2] != 0));
      let busy_rd    = (x.has_rd  && (scoreboard [rd]  != 0));
      Bool stall     = (busy_rs1 || busy_rs2 || busy_rd);

      if (stall) begin
	 // No action
	 rg_stall_count <= rg_stall_count + 1;

	 wr_log (rg_flog, $format ("CPU.rl_RR.stall: busy rd:%0d rs1:%0d rs2:%0d",
				   busy_rd, busy_rs1, busy_rs2));
	 wr_log_cont (rg_flog, $format ("    ", fshow_Decode_to_RR (x)));
	 ftrace (rg_flog, x.inum, x.pc, x.instr, "RR.S", $format (""));
      end
      else begin
	 rg_stall_count <= 0;

	 f_Decode_to_RR.deq;

	 // Read GPRs.
	 // Ok even if instr does not have rs1 or rs2
	 // values used only if relevant.
	 let rs1_val = gprs.read_rs1 (rs1);
	 let rs2_val = gprs.read_rs2 (rs2);

	 // Dispatch to one of the next-stage pipes
	 Result_Dispatch y <- fn_Dispatch (x, rs1_val, rs2_val, rg_flog);

	 // Update scoreboard for Rd
	 if (x.has_rd) begin
	    scoreboard [rd] = 1;
	    rg_scoreboard <= scoreboard;
	 end

	 // Direct to Retire
	 f_RR_to_Retire.enq (y.to_Retire);

	 wr_log (rg_flog, $format ("CPU.rl_RR:"));
	 wr_log_cont (rg_flog, $format ("    ", fshow_RR_to_Retire (y.to_Retire)));

	 // Dispatch
	 if (y.to_Retire.exec_tag == EXEC_TAG_DIRECT) begin
	    // Nothing more to do

	    wr_log_cont (rg_flog, $format ("    -> Retire:"));
	    ftrace (rg_flog, x.inum, x.pc, x.instr, "RR.X", $format (""));
	 end
	 else if (y.to_Retire.exec_tag == EXEC_TAG_CONTROL) begin
	    f_RR_to_EX_Control.enq (y.to_EX_Control);

	    wr_log_cont (rg_flog, $format ("    -> control:"));
	    wr_log_cont (rg_flog, $format ("    ",
					   fshow_RR_to_EX_Control (y.to_EX_Control)));
	    ftrace (rg_flog, x.inum, x.pc, x.instr, "RR.C", $format (""));
	 end
	 else if (y.to_Retire.exec_tag == EXEC_TAG_INT) begin
	    f_RR_to_EX_Int.enq (y.to_EX);

	    wr_log_cont (rg_flog, $format ("    -> Int:"));
	    wr_log_cont (rg_flog, $format ("    ", fshow_RR_to_EX (y.to_EX)));
	    ftrace (rg_flog, x.inum, x.pc, x.instr, "RR.I", $format (""));
	 end
	 else if (y.to_Retire.exec_tag == EXEC_TAG_DMEM) begin
	    Mem_Req mem_req <- fn_DMem_Req (rg_flog, y.to_EX);
	    f_DMem_S_req.enq (mem_req);

	    wr_log_cont (rg_flog, $format ("    -> DMem:"));
	    wr_log_cont (rg_flog, $format ("    ", fshow_RR_to_EX (y.to_EX)));
	    wr_log_cont (rg_flog, $format ("    ", fshow_Mem_Req (mem_req)));
	    ftrace (rg_flog, x.inum, x.pc, x.instr, "RR.D", $format (""));
	 end
	 else begin
	    wr_log_cont (rg_flog, $format ("    -> IMPOSSIBLE"));
	    ftrace (rg_flog, x.inum, x.pc, x.instr, "RR.IMPOSSIBLE", $format (""));

	    // IMPOSSIBLE
	    $finish (1);
	 end
      end
   endrule

   // ================================================================
   // BEHAVIOR: Backward: reg write from retire

   rule rl_RW_from_Retire;
      let x <- pop_o (to_FIFOF_O (f_RW_from_Retire));

      Scoreboard scoreboard = rg_scoreboard;
      scoreboard [x.rd] = 0;
      rg_scoreboard <= scoreboard;

      if (x.commit)
	 gprs.write_rd (x.rd, x.data);

      // ---------------- DEBUG
      let cy <- cur_cycle;
      wr_log (rg_flog, $format ("%0d: CPU.S3.rl_RW_from_Retire:", cy));
      wr_log (rg_flog, fshow_RW_from_Retire (x));
      ftrace (rg_flog, x.inum, x.pc, x.instr, "RW", $format (""));
   endrule

   // ================================================================
   // INTERFACE

   method Action init (Initial_Params initial_params);
      rg_flog <= initial_params.flog;
   endmethod

   // Forward in
   interface fi_Decode_to_RR = to_FIFOF_I (f_Decode_to_RR);

   // Forward out
   interface fo_RR_to_Retire     = to_FIFOF_O (f_RR_to_Retire);
   interface fo_RR_to_EX_Control = to_FIFOF_O (f_RR_to_EX_Control);
   interface fo_RR_to_EX_Int     = to_FIFOF_O (f_RR_to_EX_Int);
   interface fo_DMem_S_req       = to_FIFOF_O (f_DMem_S_req);

   // Backward in
   interface fi_RW_from_Retire = to_FIFOF_I (f_RW_from_Retire);
endmodule

// ****************************************************************

endpackage
