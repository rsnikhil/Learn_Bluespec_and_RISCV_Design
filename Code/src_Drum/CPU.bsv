// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package CPU;

// ****************************************************************
// Top-level of unpipelined CPU.
// * State machine performing each of the "steps" of an instruction.
// * Lifts IMem and DMem connections up to next level up.

// ****************************************************************
// Imports from libraries

import FIFOF  :: *;
import Assert :: *;

// ----------------
// Imports from 'vendor' libs

import Cur_Cycle  :: *;
import Semi_FIFOF :: *;

// ----------------
// Local imports

import Utils        :: *;
import Retire_Utils :: *;

import Arch        :: *;
import Instr_Bits  :: *;
import CSR_Bits    :: *;
import Mem_Req_Rsp :: *;
import Inter_Stage :: *;
import CPU_IFC     :: *;
import GPRs        :: *;
import CSRs        :: *;

// Functions for each step
import Fn_Fetch    :: *;
import Fn_Decode   :: *;
import Fn_Dispatch :: *;

import Fn_EX_Control :: *;
import Fn_EX_Int     :: *;

// ****************************************************************
// Choose either FSM version or explicit-rules version

`ifndef DRUM_RULES

import StmtFSM :: *;

String cpu_name = "Drum v0.81 2024-08-09 (FSM)";

`else

String cpu_name = "Drum v0.81 2024-08-09 (Rules)";

typedef enum {
   A_FETCH,
   A_DECODE,
   A_REGISTER_READ_AND_DISPATCH,
   A_EX,
   A_RETIRE_CONTROL,
   A_RETIRE_INT,
   A_RETIRE_DMEM,
   A_EXCEPTION
} CPU_ACTION
deriving (Bits, Eq, FShow);

`endif

// ****************************************************************

(* synthesize *)
module mkCPU (CPU_IFC);
   // ================================================================
   // STATE

   // Don't run until the PC (and other things) are initialized
   Reg #(Bool) rg_running <- mkReg (False);

   // For debugging in simulation only
   Reg #(File) rg_flog <- mkReg (InvalidFile);

   Reg #(Bit #(64)) rg_inum <- mkReg (0);    // For debugging only

   // The Program Counter
   Reg #(Bit #(XLEN)) rg_pc   <- mkReg (0);

   // General-Purpose Registers (GPRs)
   GPRs_IFC #(XLEN)  gprs <- mkGPRs_synth;

   // Control-and-Status Registers (CSRs)
   CSRs_IFC csrs <- mkCSRs;

   // Inter-step registers
   Reg #(Fetch_to_Decode)      rg_Fetch_to_Decode      <- mkRegU;
   Reg #(Decode_to_RR)         rg_Decode_to_RR         <- mkRegU;
   Reg #(Result_Dispatch)      rg_Dispatch             <- mkRegU;
   Reg #(EX_Control_to_Retire) rg_EX_Control_to_Retire <- mkRegU;
   Reg #(EX_to_Retire)         rg_EX_to_Retire         <- mkRegU;

   // Paths to and from memory
   FIFOF #(Mem_Req) f_IMem_req  <- mkFIFOF;
   FIFOF #(Mem_Rsp) f_IMem_rsp  <- mkFIFOF;

   FIFOF #(Mem_Req) f_DMem_req  <- mkFIFOF;
   FIFOF #(Mem_Rsp) f_DMem_rsp  <- mkFIFOF;

   // Regs to set up exception handling
   Reg #(Bool)        rg_exception <- mkReg (False);
   Reg #(Bit #(XLEN)) rg_epc       <- mkRegU;
   Reg #(Bit #(4))    rg_cause     <- mkRegU;
   Reg #(Bit #(XLEN)) rg_tval      <- mkRegU;

   // ****************************************************************
   // BEHAVIOR: Actions

   // ================================================================
   // Common functions used in many Retire actions

   function Action fa_update_rd (RR_to_Retire x1,
				 Bit #(XLEN) rd_val);
      action
	 if (x1.has_rd) begin
	    let rd = instr_rd (x1.instr);
	    gprs.write_rd (rd, rd_val);

	    wr_log (rg_flog,
		    $format ("    CPU.fa_update_rd: rd:%0d rd_val:%08h",
			     rd, rd_val));
	 end
      endaction
   endfunction

   function Action fa_redirect_Fetch (Bit #(XLEN) next_pc);
      action
	 rg_pc   <= next_pc;
	 rg_inum <= rg_inum + 1;
      endaction
   endfunction

   function Action fa_setup_exception (Bit #(XLEN) epc,
				       Bit #(4) cause,
				       Bit #(XLEN) tval);
      action
	 rg_exception <= True;
	 rg_epc       <= epc;
	 rg_cause     <= cause;
	 rg_tval      <= tval;
      endaction
   endfunction

   // ================================================================
   // Major CPU actions

   // ----------------------------------------------------------------
   Action a_Fetch =
   action

      let predicted_pc = 0;
      let epoch        = 0;
      let y <- fn_Fetch (rg_pc,
			 predicted_pc, epoch, rg_inum, rg_flog);

      rg_Fetch_to_Decode <= y.to_D;
      f_IMem_req.enq (y.mem_req);

      log_Fetch (rg_flog, y.to_D, y.mem_req);
   endaction;

   // ----------------------------------------------------------------
   Action a_Decode =
   action
      let mem_rsp <- pop_o (to_FIFOF_O (f_IMem_rsp));
      let y       <- fn_Decode (rg_Fetch_to_Decode, mem_rsp, rg_flog);
      rg_Decode_to_RR <= y;

      log_Decode (rg_flog, y, mem_rsp);
   endaction;

   // ----------------------------------------------------------------
   Action a_Register_Read_and_Dispatch =
   action
      // Read GPRs
      // Ok that read_rs1 and read_rs2 may return junk values
      //         since not all instrs have rs1/rs2.
      let x       = rg_Decode_to_RR;
      let rs1_val = gprs.read_rs1 (instr_rs1 (x.instr));
      let rs2_val = gprs.read_rs2 (instr_rs2 (x.instr));

      Result_Dispatch y <- fn_Dispatch (x, rs1_val, rs2_val, rg_flog);
      rg_Dispatch       <= y;

      // ---------------- Logging
      case (y.to_Retire.exec_tag)
	 EXEC_TAG_DIRECT:  log_Dispatch_Direct (rg_flog, y.to_Retire);
	 EXEC_TAG_CONTROL: log_Dispatch_Control (rg_flog, y.to_Retire, y.to_EX_Control);
	 EXEC_TAG_INT:     log_Dispatch_Int (rg_flog, y.to_Retire, y.to_EX);
	 EXEC_TAG_DMEM:    log_Dispatch_DMem (rg_flog, y.to_Retire, y.to_EX, y.to_EX_DMem);
	 default: begin
		     wr_log (rg_flog, $format ("CPU.Dispatch:"));
		     wr_log_cont (rg_flog,
				  $format ("    ", fshow_RR_to_Retire (y.to_Retire)));
		     wr_log_cont (rg_flog, $format ("    -> IMPOSSIBLE"));
		     // IMPOSSIBLE
		     $finish (1);
		  end
      endcase
   endaction;

   // ----------------------------------------------------------------
   Action a_Retire_direct =
   action
      let x_direct = rg_Dispatch.to_Retire;
      if (x_direct.exception) begin
	 fa_setup_exception (x_direct.pc,        // epc
			     x_direct.cause,     // cause
			     x_direct.tval);     // tval
	 log_Retire_Direct_exc (rg_flog, x_direct);
      end
      // ----------------
      else if (is_legal_CSRRxx (x_direct.instr)) begin
	 match { .exc, .rd_val } <- csrs.mav_csrrxx (x_direct.instr,
						     x_direct.rs1_val);
	 if (exc)
	    fa_setup_exception (x_direct.pc,                  // epc
				cause_ILLEGAL_INSTRUCTION,    // cause
				x_direct.instr);              // tval
	 else begin
	    fa_update_rd (x_direct, rd_val);
	    fa_redirect_Fetch (x_direct.fallthru_pc);
	 end
	 log_Retire_CSRRxx (rg_flog, exc, x_direct);
      end
      // ----------------
      else if (is_legal_MRET (x_direct.instr)) begin
	 let new_pc <- csrs.mav_xRET;
	 fa_redirect_Fetch (new_pc);
	 csrs.ma_incr_instret;
	 log_Retire_MRET (rg_flog, x_direct);
      end
      // ----------------
      else if (is_legal_ECALL (x_direct.instr)
	       || is_legal_EBREAK (x_direct.instr))
	 begin
	    let cause = ((x_direct.instr [20] == 0)
			 ? cause_ECALL_FROM_M
			 : cause_BREAKPOINT);
	    fa_setup_exception (x_direct.pc,    // epc
				cause,
				0);             // tval
	    csrs.ma_incr_instret;
	    log_Retire_ECALL_EBREAK (rg_flog, x_direct);
	 end
      else begin
	 wr_log2 (rg_flog, $format ("CPU.EX.Direct: IMPOSSIBLE"));
	 $finish (1);
      end
   endaction;

   // ----------------------------------------------------------------
   Action a_EX_Control =
   action
      let x = rg_Dispatch.to_EX_Control;
      let y <- fn_EX_Control (x, rg_flog);
      rg_EX_Control_to_Retire <= y;

      log_EX_Control (rg_flog, x, y);
   endaction;

   // ----------------
   Action a_Retire_Control =
   action
      let x_direct  = rg_Dispatch.to_Retire;
      let x_control = rg_EX_Control_to_Retire;
      if (x_control.exception)
	 fa_setup_exception (x_direct.pc,
			     x_control.cause,
			     x_control.tval);
      else begin
	 fa_update_rd (x_direct, x_control.data);
	 fa_redirect_Fetch (x_control.next_pc);
	 csrs.ma_incr_instret;
      end

      log_Retire_Control (rg_flog, x_control.exception,
			  x_direct, x_control);
   endaction;

   // ----------------------------------------------------------------
   Action a_EX_Int =
   action
      let x = rg_Dispatch.to_EX;
      let y <- fn_EX_Int (x, rg_flog);
      rg_EX_to_Retire <= y;

      log_EX_Int (rg_flog, x, y);
   endaction;

   // ----------------
   Action a_Retire_Int =
   action
      if (rg_EX_to_Retire.exception)
	 fa_setup_exception (rg_Dispatch.to_Retire.pc,
			     rg_EX_to_Retire.cause,
			     rg_EX_to_Retire.tval);
      else begin
	 fa_update_rd (rg_Dispatch.to_Retire, rg_EX_to_Retire.data);
	 fa_redirect_Fetch (rg_Dispatch.to_Retire.fallthru_pc);
	 csrs.ma_incr_instret;
      end

      log_Retire_Int (rg_flog, rg_EX_to_Retire.exception,
		      rg_Dispatch.to_Retire, rg_EX_to_Retire);
   endaction;

   // ----------------------------------------------------------------
   Action a_EX_DMem =
   action
      Mem_Req y = rg_Dispatch.to_EX_DMem;
      f_DMem_req.enq (y);

      log_DMem_NS_req (rg_flog, rg_Dispatch.to_Retire, y);
   endaction;

   // ----------------
   Action a_Retire_DMem =
   action
      let x_direct = rg_Dispatch.to_Retire;
      let mem_rsp <- pop_o (to_FIFOF_O (f_DMem_rsp));

      dynamicAssert ((mem_rsp.rsp_type != MEM_REQ_DEFERRED),
		     "Mem req not speculative but got DEFERRED mem response");

      Bool exception = ((mem_rsp.rsp_type == MEM_RSP_ERR)
			|| (mem_rsp.rsp_type == MEM_RSP_MISALIGNED));
      if (exception) begin
	 Bit #(4) cause = ((mem_rsp.rsp_type == MEM_RSP_MISALIGNED)
			   ? (is_LOAD (x_direct.instr)
			      ? cause_LOAD_ADDRESS_MISALIGNED
			      : cause_STORE_AMO_ADDRESS_MISALIGNED)
			   : (is_LOAD (x_direct.instr)
			      ? cause_LOAD_ACCESS_FAULT
			      : cause_STORE_AMO_ACCESS_FAULT));
	 fa_setup_exception (x_direct.pc,                 // epc
			     cause,
			     truncate (mem_rsp.addr));    // tval
      end
      else begin
	 let data = mem_rsp.data;
	 if (instr_opcode (x_direct.instr) == opcode_LOAD) begin
	    if (instr_funct3 (x_direct.instr) == funct3_LB)
	       data = signExtend (data [7:0]);
	    else if (instr_funct3 (x_direct.instr) == funct3_LH)
	       data = signExtend (data [15:0]);
	    // TODO: LW in RV64
	 end
	 fa_update_rd (x_direct, truncate (data));
	 fa_redirect_Fetch (x_direct.fallthru_pc);
	 csrs.ma_incr_instret;
      end

      log_DMem_NS_rsp (rg_flog, exception, x_direct, mem_rsp);
   endaction;

   // ----------------------------------------------------------------
   Action a_exception =
   action
      Bool is_interrupt = False;
      Bit #(XLEN) tvec_pc <- csrs.mav_exception (rg_epc,
						 is_interrupt,
						 rg_cause,
						 rg_tval);
      rg_exception <= False;
      fa_redirect_Fetch (tvec_pc);

      log_Retire_exception (rg_flog, rg_Dispatch.to_Retire,
			    rg_epc, is_interrupt, rg_cause, rg_tval);
   endaction;

   // ****************************************************************
   // BEHAVIOR: FSM or Rules versions

`ifndef DRUM_RULES

`include "Drum_FSM.bsv"

`else

`include "Drum_Rules.bsv"

`endif

   // ****************************************************************
   // BEHAVIOR: Debugger support

   `include "CPU_Dbg.bsv"

   // ****************************************************************
   // INTERFACE

   method Action init (Initial_Params initial_params);
      rg_flog    <= initial_params.flog;

      rg_pc      <= initial_params.pc_reset_value;
      rg_running <= True;
      csrs.init (initial_params);

      $display ("================================================================");
      $display ("%s: starting execution at PC %0h",
		cpu_name, initial_params.pc_reset_value);

      if (initial_params.flog != InvalidFile) begin
	 $fdisplay (initial_params.flog,
		    "================================================================");
	 $fdisplay (initial_params.flog, "%s: starting execution at PC %0h",
		    cpu_name, initial_params.pc_reset_value);
      end

   endmethod

   // IMem
   interface fo_IMem_req = to_FIFOF_O (f_IMem_req);
   interface fi_IMem_rsp = to_FIFOF_I (f_IMem_rsp);

   // DMem, speculative
   interface fo_DMem_S_req    = dummy_FIFOF_O;
   interface fi_DMem_S_rsp    = dummy_FIFOF_I;
   interface fo_DMem_S_commit = dummy_FIFOF_O;

   // DMem, non-speculative
   interface fo_DMem_req = to_FIFOF_O (f_DMem_req);
   interface fi_DMem_rsp = to_FIFOF_I (f_DMem_rsp);

   // Set TIME
   method Action set_TIME (Bit #(64) t) = csrs.set_TIME (t);

   // Debugger support
   // Requests from/responses to remote debugger
   interface fi_dbg_to_CPU_pkt   = to_FIFOF_I (f_dbg_to_CPU_pkt);
   interface fo_dbg_from_CPU_pkt = to_FIFOF_O (f_dbg_from_CPU_pkt);
   // Memory requests/responses for remote debugger
   interface fo_dbg_to_mem_req   = to_FIFOF_O (f_dbg_to_mem_req);
   interface fi_dbg_from_mem_rsp = to_FIFOF_I (f_dbg_from_mem_rsp);
endmodule

// ****************************************************************

endpackage
