// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package CPU;

// ****************************************************************
// Top-level of unpipelined CPU.
// * State machine performing each of the "steps" of an instruction.
// * Lifts IMem and DMem connections up to next level up.

// ****************************************************************
// Imports from libraries

import FIFOF   :: *;
import StmtFSM :: *;

// ----------------
// Imports from 'vendor' libs

import Cur_Cycle  :: *;
import Semi_FIFOF :: *;

// ----------------
// Local imports

import Utils       :: *;

import Arch        :: *;
import Instr_Bits  :: *;
import CSR_Bits    :: *;
import Mem_Req_Rsp :: *;
import Inter_Stage :: *;
import CPU_IFC     :: *;
import RISCV_GPRs  :: *;
import CSRs        :: *;

// Functions for each step
import Fn_Fetch    :: *;
import Fn_Decode   :: *;
import Fn_Dispatch :: *;

import Fn_EX_Control :: *;
import Fn_EX_Int     :: *;
import Fn_EX_DMem    :: *;

// ****************************************************************

String cpu_name = "Drum v0.7 2024-02-01";

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

   // The integer register file
   RISCV_GPRs_IFC #(XLEN)  gprs <- mkRISCV_GPRs_synth;

   // CSRs
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

   function Action fa_redirect_Fetch (Bit #(XLEN) next_pc);
      action
	 rg_pc   <= next_pc;
	 rg_inum <= rg_inum + 1;
      endaction
   endfunction


   // ================================================================
   // FSM for Drum behavior

   Stmt exec_one_instr =
   seq



      // ================================================================
      // Fetch
      action

	 let predicted_pc = 0;
	 let epoch        = 0;
	 let y <- fn_Fetch (rg_pc,
			    predicted_pc, epoch, rg_inum, rg_flog);

	 rg_Fetch_to_Decode <= y.to_D;
	 f_IMem_req.enq (y.mem_req);


	 wr_log (rg_flog, $format ("CPU.rl_F: ", fshow_Fetch_to_Decode (y.to_D)));
	 wr_log_cont (rg_flog, fshow_Mem_Req (y.mem_req));
      endaction

      // ================================================================
      // Decode
      action
	 let mem_rsp <- pop_o (to_FIFOF_O (f_IMem_rsp));
	 let y       <- fn_Decode (rg_Fetch_to_Decode, mem_rsp, rg_flog);
	 rg_Decode_to_RR <= y;


	 wr_log (rg_flog,
		 $format ("CPU.rl_D: ", fshow_Decode_to_RR (y)));
      endaction

      // ================================================================
      // Register-Read and Dispatch
      action
	 // Read GPRs
	 // Ok that read_rs1 and read_rs2 may return junk values
	 //         since not all instrs have rs1/rs2.
	 let x       = rg_Decode_to_RR;
	 let rs1_val = gprs.read_rs1 (instr_rs1 (x.instr));
	 let rs2_val = gprs.read_rs2 (instr_rs2 (x.instr));

	 Result_Dispatch y <- fn_Dispatch (x, rs1_val, rs2_val, rg_flog);
	 rg_Dispatch       <= y;


	 wr_log (rg_flog, $format ("CPU.RR: inum:%0d pc:%08h instr:%08h",
				   x.inum, x.pc, x.instr));
	 wr_log_cont (rg_flog, $format ("        rs1_val:%08h rs2_val:%08h",
					rs1_val, rs2_val));
	 wr_log_cont (rg_flog, $format ("        ", fshow_RR_to_Retire (y.to_Retire)));
	 wr_log_cont (rg_flog, $format ("        ", fshow_RR_to_EX     (y.to_EX)));
	 wr_log_cont (rg_flog,
		      $format ("        ", fshow_Mem_Req      (y.to_EX_DMem)));
      endaction
      // ================================================================
      // Execute and Retire
      if (rg_Dispatch.to_Retire.exec_tag == EXEC_TAG_DIRECT)
	 action
	    let x_direct = rg_Dispatch.to_Retire;
	    if (x_direct.exception)
	       fa_setup_exception (x_direct.pc,        // epc
				   x_direct.cause,     // cause
				   x_direct.tval);     // tval
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
	    end
	    else if (is_legal_MRET (x_direct.instr))
	       fa_redirect_Fetch (csrs.read_epc);
	    else if (is_legal_ECALL (x_direct.instr)
		     || is_legal_EBREAK (x_direct.instr)) begin
               let cause = ((x_direct.instr [20] == 0)
			    ? cause_ECALL_FROM_M
			    : cause_BREAKPOINT);
	       fa_setup_exception (x_direct.pc,    // epc
				   cause,
				   0);             // tval
	    end
	    else begin
	       wr_log (rg_flog, $format ("CPU.EX.Direct: IMPOSSIBLE"));
	       $finish (1);
	    end
	 endaction
      // ---------------- CONTROL (BRANCH, JAL, JALR)
      else if (rg_Dispatch.to_Retire.exec_tag == EXEC_TAG_CONTROL)
	 seq
	    // ---------------- Execute
	    action
	       let y <- fn_EX_Control (rg_Dispatch.to_EX_Control, rg_flog);
	       rg_EX_Control_to_Retire <= y;
	    endaction
	    // ---------------- Retire
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
	       end

	       // ---------------- DEBUG
	       if (x_control.exception) begin
		  ftrace (rg_flog,
			  x_direct.inum,
			  x_direct.pc,
			  x_direct.instr,
			  "RET.C.X", $format (""));
		  wr_log (rg_flog, $format ("CPU.S5.Retire_EX_Control: Exception"));
	       end
	       else begin
		  ftrace (rg_flog,
			  x_direct.inum,
			  x_direct.pc,
			  x_direct.instr,
			  "RET.C", $format (""));
		  wr_log (rg_flog, $format ("CPU.S5.Retire_EX_Control: Normal"));
	       end
	       wr_log_cont (rg_flog,
			    $format ("    ",
				     fshow_EX_Control_to_Retire (x_control)));
	    endaction
	 endseq
      // ---------------- INTEGER (LUI, AUIPC, IALU)
      else if (rg_Dispatch.to_Retire.exec_tag == EXEC_TAG_INT)
	 seq
	    // ---------------- Execute
	    action
	       let y <- fn_EX_Int (rg_Dispatch.to_EX, rg_flog);
	       rg_EX_to_Retire <= y;

	       wr_log (rg_flog, $format ("CPU.EX_Int: ", fshow_EX_to_Retire (y)));
	    endaction
	    // ---------------- Retire
	    action
	       if (rg_EX_to_Retire.exception)
		  fa_setup_exception (rg_Dispatch.to_Retire.pc,
				      rg_EX_to_Retire.cause,
				      rg_EX_to_Retire.tval);
	       else begin
		  fa_update_rd (rg_Dispatch.to_Retire, rg_EX_to_Retire.data);
		  fa_redirect_Fetch (rg_Dispatch.to_Retire.fallthru_pc);
	       end
	    endaction
	 endseq
      // ---------------- DMEM
      else if (rg_Dispatch.to_Retire.exec_tag == EXEC_TAG_DMEM)
	 seq
	    // ---------------- Execute: send DMem req
	    action
	       Mem_Req y = rg_Dispatch.to_EX_DMem;
	       f_DMem_req.enq (y);

	       wr_log (rg_flog, $format ("CPU.EX_DMem_Req:", fshow_Mem_Req (y)));
	    endaction
	    // ---------------- Retire: process DMem rsp
	    action
	       let x_direct = rg_Dispatch.to_Retire;
	       let mem_rsp <- pop_o (to_FIFOF_O (f_DMem_rsp));
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
		  fa_update_rd (x_direct, truncate (mem_rsp.data));
		  fa_redirect_Fetch (x_direct.fallthru_pc);
	       end

	       wr_log (rg_flog, $format ("CPU.EX_DMem_Rsp:"));
	       let show_data = (! is_STORE (x_direct.instr));
	       wr_log_cont (rg_flog, $format ("     ",
					      fshow_Mem_Rsp (mem_rsp, show_data)));
	       wr_log_cont (rg_flog, $format ("     ",
					      fshow_RR_to_Retire (x_direct)));
	    endaction
	 endseq
      else
	 action
	    wr_log (rg_flog, $format ("    -> IMPOSSIBLE"));
	    $finish (0);
	 endaction
      // ================================================================
      // Exceptions
      if (rg_exception)
	 action
	    Bool is_interrupt = False;
	    Bit #(XLEN) tvec_pc <- csrs.mav_exception (rg_epc,
						       is_interrupt,
						       rg_cause,
						       rg_tval);
	    rg_exception <= False;
	    fa_redirect_Fetch (tvec_pc);
	 endaction
   endseq;

   mkAutoFSM (seq
                 await (rg_running);
		 while (True) exec_one_instr;
	      endseq);


   // ****************************************************************
   // INTERFACE

   method Action init (Initial_Params initial_params);
      rg_flog    <= initial_params.flog;

      rg_pc      <= initial_params.pc_reset_value;
      rg_running <= True;
   endmethod

   interface fo_IMem_req = to_FIFOF_O (f_IMem_req);
   interface fi_IMem_rsp = to_FIFOF_I (f_IMem_rsp);

   // These are speculative DMem interfaces, used in Fife, not Drum
   interface fo_DMem_S_req    = dummy_FIFOF_O;
   interface fi_DMem_S_rsp    = dummy_FIFOF_I;
   interface fo_DMem_S_commit = dummy_FIFOF_O;

   interface fo_DMem_req = to_FIFOF_O (f_DMem_req);
   interface fi_DMem_rsp = to_FIFOF_I (f_DMem_rsp);
endmodule

// ****************************************************************

endpackage
