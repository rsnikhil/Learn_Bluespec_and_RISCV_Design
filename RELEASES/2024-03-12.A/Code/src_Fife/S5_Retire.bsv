// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package S5_Retire;

// ****************************************************************
// Imports from libraries

import FIFOF        :: *;
import SpecialFIFOs :: *;    // For mkPipelineFIFOF and mkBypassFIFOF

// ----------------
// Imports from 'vendor' libs

import Cur_Cycle  :: *;
import Semi_FIFOF :: *;

// ----------------
// Local imports

import Utils       :: *;
import Arch        :: *;
import Instr_Bits  :: *;
import CSR_Bits    :: *;    // For trap CAUSE
import Inter_Stage :: *;
import Mem_Req_Rsp :: *;

import Fn_EX_DMem   :: *;
import CSRs         :: *;
import Retire_Utils :: *;

// ****************************************************************

interface Retire_IFC;
   method Action init (Initial_Params initial_params);

   // Forward in
   interface FIFOF_I #(RR_to_Retire)          fi_RR_to_Retire;
   interface FIFOF_I #(EX_Control_to_Retire)  fi_EX_Control_to_Retire;
   interface FIFOF_I #(EX_to_Retire)          fi_EX_Int_to_Retire;
   // Speculative DMem response
   interface FIFOF_I #(Mem_Rsp)               fi_DMem_S_rsp;

   // Store buffer commit/discard
   interface FIFOF_O #(Retire_to_DMem_Commit) fo_DMem_S_commit;

   // Non-speculative DMem
   interface FIFOF_O #(Mem_Req)  fo_DMem_req;
   interface FIFOF_I #(Mem_Rsp)  fi_DMem_rsp;

   // Backward out
   interface FIFOF_O #(Fetch_from_Retire)  fo_Fetch_from_Retire;
   interface FIFOF_O #(RW_from_Retire)     fo_RW_from_Retire;
endinterface

// ****************************************************************

typedef enum {MODE_PIPE,        // Normal pipeline operation
	      MODE_DMEM_RSP,    // Handle Non-speculative DMem response
	      MODE_EXCEPTION
} Module_Mode
deriving (Bits, Eq, FShow);

// ****************************************************************

(* synthesize *)
module mkRetire (Retire_IFC);
   Reg #(File) rg_flog <- mkReg (InvalidFile);    // debugging

   // CSRs
   CSRs_IFC csrs <- mkCSRs;

   // For managing speculation, redirection, traps, etc.
   Reg #(Epoch) rg_epoch  <- mkReg (0);

   // Forward in
   // Depth of f_RR_to_Retire should be > longest EX pipe
   FIFOF #(RR_to_Retire)          f_RR_to_Retire         <- mkSizedFIFOF (8);
   FIFOF #(EX_Control_to_Retire)  f_EX_Control_to_Retire <- mkPipelineFIFOF;
   FIFOF #(EX_to_Retire)          f_EX_Int_to_Retire     <- mkPipelineFIFOF;
   FIFOF #(Mem_Rsp)               f_DMem_S_rsp           <- mkPipelineFIFOF;

   // Forward out
   FIFOF #(Retire_to_DMem_Commit) f_DMem_S_commit  <- mkBypassFIFOF;

   // Backward out
   FIFOF #(Fetch_from_Retire) f_Fetch_from_Retire <- mkBypassFIFOF;
   FIFOF #(RW_from_Retire)    f_RW_from_Retire    <- mkBypassFIFOF;

   // Non-speculative DMem reqs and rsps
   FIFOF #(Mem_Req)  f_DMem_req  <- mkBypassFIFOF;
   FIFOF #(Mem_Rsp)  f_DMem_rsp  <- mkPipelineFIFOF;

   Reg #(Module_Mode) rg_mode <- mkReg (MODE_PIPE);

   // Regs to set up exception handling
   Reg #(Bit #(XLEN)) rg_epc   <- mkRegU;
   Reg #(Bit #(4))    rg_cause <- mkRegU;
   Reg #(Bit #(XLEN)) rg_tval  <- mkRegU;

   // One-instr-at-a-time (unpipelined) control
   Reg #(Bool) rg_oiaat <- mkReg (False);

   // ****************************************************************
   // BEHAVIOR

   // ================================================================
   // Functions for actions used in many rules


   function Action fa_redirect_Fetch (Bool         mispredicted,
				      RR_to_Retire x1,
				      Bit #(XLEN)  next_pc);
      action
	 if (mispredicted || rg_oiaat) begin
	    let next_epoch = rg_epoch + 1;
	    rg_epoch <= next_epoch;
	    let y = Fetch_from_Retire {next_pc:    next_pc,
				       next_epoch: next_epoch,
				       inum:       x1.inum,
				       pc:         x1.pc,
				       instr:      x1.instr};
	    f_Fetch_from_Retire.enq (y);

	    // ---------------- DEBUG
	    wr_log (rg_flog, $format ("    CPU.S5.fa_redirect_Fetch:\n    ",
				      fshow_Fetch_from_Retire (y)));
	 end
      endaction
   endfunction


   // * unreserve the scoreboard
   // * if commit, also write the rd_val
   function Action fa_update_rd (RR_to_Retire x1,
				 Bool         commit,
				 Bit #(XLEN)  rd_val);
      action
	 if (x1.has_rd) begin
	    let y = RW_from_Retire {rd:         instr_rd (x1.instr),
				    commit:     commit,
				    data:       rd_val,
				    inum:       x1.inum,
				    pc:         x1.pc,
				    instr:      x1.instr};
	    f_RW_from_Retire.enq (y);

	    // ---------------- DEBUG
	    Fmt fmt = $format ("    CPU.S5.fa_update_rd:");
	    if (! commit)
	       fmt = fmt + $format ("(unreserve scoreboard)");
	    fmt = fmt + $format ("\n      ", fshow_RW_from_Retire (y));
	    wr_log (rg_flog, fmt);
	 end
      endaction
   endfunction


   function Action fa_retire_store_buf (RR_to_Retire x1,
					Mem_Rsp      mem_rsp,
					Bool         commit);
      action
	 if (x1.writes_mem && (mem_rsp.rsp_type == MEM_RSP_OK)) begin
	    let y = Retire_to_DMem_Commit{commit: commit,
					  inum: x1.inum};

	    f_DMem_S_commit.enq (y);
	 end
      endaction
   endfunction

   // ================================================================
   // Instruction-Merge control


   // mispredictions and in-order merging of all pipes.
   RR_to_Retire x_rr_to_retire = f_RR_to_Retire.first;

   Bool wrong_path = (x_rr_to_retire.epoch != rg_epoch);
   Bool is_Direct  = (x_rr_to_retire.exec_tag == EXEC_TAG_DIRECT);
   Bool is_Control = (x_rr_to_retire.exec_tag == EXEC_TAG_CONTROL);
   Bool is_Int     = (x_rr_to_retire.exec_tag == EXEC_TAG_INT);
   Bool is_DMem    = (x_rr_to_retire.exec_tag == EXEC_TAG_DMEM);

   // ================================================================
   // Wrong-path; ignore and discard (all pipes)

   rule rl_Retire_wrong_path ((rg_mode == MODE_PIPE)
			      && wrong_path);
      f_RR_to_Retire.deq;

      // Unreserve/commit rd if needed
      fa_update_rd (x_rr_to_retire, False, ?);

      // Discard related pipe
      if (is_Control) f_EX_Control_to_Retire.deq;
      if (is_Int)     f_EX_Int_to_Retire.deq;
      if (is_DMem) begin
	 let mem_rsp <- pop_o (to_FIFOF_O (f_DMem_S_rsp));
	 // Send 'discard' (False) to store-buf, if needed
	 fa_retire_store_buf (x_rr_to_retire, mem_rsp, False);
      end

      // ---------------- DEBUG
      ftrace (rg_flog, x_rr_to_retire.inum, x_rr_to_retire.pc, x_rr_to_retire.instr,
	      "RET.discard", $format (""));
      wr_log (rg_flog, $format ("CPU.S5.rl_Retire_wrong_path:\n    ",
				+ fshow_RR_to_Retire (x_rr_to_retire)));
   endrule

   // ================================================================
   // Retire RR Direct

   // ----------------
   // RR direct: CSRRxx

   rule rl_Retire_CSRRxx ((rg_mode == MODE_PIPE)
			  && (! wrong_path)
			  && is_Direct
			  && (! x_rr_to_retire.exception)
			  && is_legal_CSRRxx (x_rr_to_retire.instr));
      f_RR_to_Retire.deq;

      match { .exc, .rd_val } <- csrs.mav_csrrxx (x_rr_to_retire.instr,
						  x_rr_to_retire.rs1_val);
      // Unreserve/commit rd if needed
      fa_update_rd (x_rr_to_retire, (! exc), rd_val);

      if (! exc) begin
	 Bool mispredicted = (x_rr_to_retire.predicted_pc
			      != x_rr_to_retire.fallthru_pc);
	 fa_redirect_Fetch (mispredicted,
			    x_rr_to_retire,
			    x_rr_to_retire.fallthru_pc);
      end
      else begin
	 rg_epc   <= x_rr_to_retire.pc;
	 rg_cause <= cause_ILLEGAL_INSTRUCTION;
	 rg_tval  <= x_rr_to_retire.instr;
	 rg_mode  <= MODE_EXCEPTION;
      end

      log_Retire_CSRRxx (rg_flog, exc, x_rr_to_retire);
   endrule

   // ----------------
   // RR direct: MRET

   rule rl_Retire_MRET ((rg_mode == MODE_PIPE)
			&& (! wrong_path)
			&& is_Direct
			&& (! x_rr_to_retire.exception)
			&& is_legal_MRET (x_rr_to_retire.instr));
      f_RR_to_Retire.deq;
      Bool mispredicted = True;
      fa_redirect_Fetch (mispredicted, x_rr_to_retire, csrs.read_epc);

      log_Retire_MRET (rg_flog, x_rr_to_retire);
   endrule

   // ----------------
   // RR direct: ECALL/EBREAK

   rule rl_Retire_ECALL_EBREAK ((rg_mode == MODE_PIPE)
				&& (! wrong_path)
				&& is_Direct
				&& (! x_rr_to_retire.exception)
				&& (is_legal_ECALL (x_rr_to_retire.instr)
				    || is_legal_EBREAK (x_rr_to_retire.instr)));
      rg_epc   <= x_rr_to_retire.pc;
      rg_cause <= ((x_rr_to_retire.instr [20] == 0)
		   ? cause_ECALL_FROM_M
		   : cause_BREAKPOINT);
      rg_tval  <= 0;
      rg_mode <= MODE_EXCEPTION;

      log_Retire_ECALL_EBREAK (rg_flog, x_rr_to_retire);
   endrule

   // ----------------
   // RR direct; exception

   rule rl_Retire_Direct_exception ((rg_mode == MODE_PIPE)
				    && (! wrong_path)
				    && is_Direct
				    && x_rr_to_retire.exception);
      f_RR_to_Retire.deq;

      rg_epc   <= x_rr_to_retire.pc;
      rg_cause <= x_rr_to_retire.cause;
      rg_tval  <= x_rr_to_retire.tval;
      rg_mode <= MODE_EXCEPTION;

      log_Retire_Direct_exc (rg_flog, x_rr_to_retire);

      if (x_rr_to_retire.cause == cause_ILLEGAL_INSTRUCTION) begin
	 wr_log2 (rg_flog,
		  $format ("    TEMPORARY SIM OPTION: FINISH ON ILLEGAL INSTRUCTION"));
	 $finish (1);
      end
   endrule

   // ================================================================
   // Retire EX_Control pipe

   rule rl_Retire_EX_Control ((rg_mode == MODE_PIPE)
			      && (! wrong_path)
			      && is_Control);
      f_RR_to_Retire.deq;
      let x2 <- pop_o (to_FIFOF_O (f_EX_Control_to_Retire));

      // Unreserve/commit rd if needed
      fa_update_rd (x_rr_to_retire, (! x2.exception), x2.data);

      if (! x2.exception) begin
	 // Redirect Fetch PC if mispredicted
	 Bool mispredicted = (x_rr_to_retire.predicted_pc != x2.next_pc);
	 fa_redirect_Fetch (mispredicted, x_rr_to_retire, x2.next_pc);
      end
      else begin
	 rg_epc   <= x_rr_to_retire.pc;
	 rg_cause <= x2.cause;
	 rg_tval  <= x2.tval;
	 rg_mode <= MODE_EXCEPTION;
      end

      log_Retire_Control (rg_flog, x2.exception, x_rr_to_retire, x2);
   endrule

   // ================================================================
   // Retire EX Int pipe

   rule rl_Retire_EX_Int ((rg_mode == MODE_PIPE)
			  && (! wrong_path)
			  && is_Int);
      f_RR_to_Retire.deq;
      EX_to_Retire x2 <- pop_o (to_FIFOF_O (f_EX_Int_to_Retire));

      // Unreserve/commit rd if needed
      fa_update_rd (x_rr_to_retire, (! x2.exception), x2.data);

      if (! x2.exception) begin
	 // Redirect Fetch PC if mispredicted
	 Bool mispredicted = (x_rr_to_retire.predicted_pc
			      != x_rr_to_retire.fallthru_pc);
	 fa_redirect_Fetch (mispredicted,
			    x_rr_to_retire,
			    x_rr_to_retire.fallthru_pc);
      end
      else begin
	 rg_epc   <= x_rr_to_retire.pc;
	 rg_cause <= x2.cause;
	 rg_tval  <= x2.tval;
	 rg_mode <= MODE_EXCEPTION;
      end

      log_Retire_Int (rg_flog, x2.exception, x_rr_to_retire, x2);
   endrule

   // ================================================================
   // Retire EX DMem pipe, not deferred (speculative)

   rule rl_Retire_EX_DMem ((rg_mode == MODE_PIPE)
			   && (! wrong_path)
			   && is_DMem
			   && (f_DMem_S_rsp.first.rsp_type != MEM_REQ_DEFERRED));

      f_RR_to_Retire.deq;
      let x2 <- pop_o (to_FIFOF_O (f_DMem_S_rsp));

      Bool exception = (x2.rsp_type != MEM_RSP_OK);

      // Unreserve/commit rd if needed
      fa_update_rd (x_rr_to_retire, (! exception), truncate (x2.data));

      if (! exception) begin
	 // Send 'commit' (True) to store-buf, if needed
	 fa_retire_store_buf (x_rr_to_retire, x2, True);

	 // Redirect Fetch PC if mispredicted
	 Bool mispredicted = (x_rr_to_retire.predicted_pc
			      != x_rr_to_retire.fallthru_pc);
	 fa_redirect_Fetch (mispredicted,
			    x_rr_to_retire,
			    x_rr_to_retire.fallthru_pc);
      end
      else begin
	 rg_epc   <= x_rr_to_retire.pc;
	 rg_cause <= ((x2.rsp_type == MEM_RSP_MISALIGNED)
		      ? (is_LOAD (x_rr_to_retire.instr)
			 ? cause_LOAD_ADDRESS_MISALIGNED
			 : cause_STORE_AMO_ADDRESS_MISALIGNED)
		      : (is_LOAD (x_rr_to_retire.instr)
			 ? cause_LOAD_ACCESS_FAULT
			 : cause_STORE_AMO_ACCESS_FAULT));
	 rg_tval  <= truncate (x2.addr);
	 rg_mode <= MODE_EXCEPTION;
      end

      log_Retire_DMem (rg_flog, exception, x_rr_to_retire, x2);
   endrule

   // ================================================================
   // Retire EX DMem pipe: deferred (non-speculative)

   rule rl_Retire_DMem_deferred ((rg_mode == MODE_PIPE)
				 && (! wrong_path)
				 && is_DMem
				 && (f_DMem_S_rsp.first.rsp_type
				     == MEM_REQ_DEFERRED));
      let x2 <- pop_o (to_FIFOF_O (f_DMem_S_rsp));

      // Issue DMem request
      let mem_req = Mem_Req{inum:     x2.inum,
			    pc:       x2.pc,
			    instr:    x2.instr,
			    req_type: x2.req_type,
			    size:     x2.size,
			    addr:     x2.addr,
			    data:     x2.data};
      f_DMem_req.enq (mem_req);
      rg_mode <= MODE_DMEM_RSP;    // go to await response

      log_DMem_NS_req (rg_flog, x_rr_to_retire, mem_req);
   endrule

   // ----------------------------------------------------------------
   // Handle DMem response

   rule rl_Retire_DMem_rsp (rg_mode == MODE_DMEM_RSP);
      f_RR_to_Retire.deq;
      let x2 <- pop_o (to_FIFOF_O (f_DMem_rsp));

      Bool exception = ((x2.rsp_type == MEM_RSP_ERR)
			|| (x2.rsp_type == MEM_RSP_MISALIGNED));
      if (exception) begin
	 rg_epc   <= x_rr_to_retire.pc;
	 rg_cause <= ((x2.rsp_type == MEM_RSP_MISALIGNED)
		      ? (is_LOAD (x_rr_to_retire.instr)
			 ? cause_LOAD_ADDRESS_MISALIGNED
			 : cause_STORE_AMO_ADDRESS_MISALIGNED)
		      : (is_LOAD (x_rr_to_retire.instr)
			 ? cause_LOAD_ACCESS_FAULT
			 : cause_STORE_AMO_ACCESS_FAULT));
	 rg_tval  <= truncate (x2.addr);
	 rg_mode <= MODE_EXCEPTION;
      end
      else if (x2.rsp_type == MEM_REQ_DEFERRED) begin
	 wr_log2 (rg_flog, ($format ("INTERNAL_ERROR: CPU.rl_Retire_DMem_rsp:")
			    + $format ("\n    ", fshow_Mem_Rsp (x2, True))
			    + $format ("\n    Unexpected MEM_REQ_DEFERRED; QUIT.")));

	 // IMPOSSIBLE. Non-speculative requests cannot be deferred
	 $finish (1);
      end
      else begin
	 // Unreserve/commit rd if needed
	 fa_update_rd (x_rr_to_retire, True, truncate (x2.data));

	 // Redirect Fetch to correct mispredicted PC
	 Bool mispredicted = (x_rr_to_retire.predicted_pc
			      != x_rr_to_retire.fallthru_pc);
	 fa_redirect_Fetch (mispredicted,
			    x_rr_to_retire,
			    x_rr_to_retire.fallthru_pc);

	 // Resume pipeline behavior
	 rg_mode <= MODE_PIPE;
      end

      log_DMem_NS_rsp (rg_flog, exception, x_rr_to_retire, x2);
   endrule

   // ================================================================
   // All exceptions

   rule rl_exception (rg_mode == MODE_EXCEPTION);
      Bool is_interrupt = False;
      Bit #(XLEN) tvec_pc <- csrs.mav_exception (rg_epc,
						 is_interrupt,
						 rg_cause,
						 rg_tval);
      fa_redirect_Fetch (True, x_rr_to_retire, tvec_pc);
      rg_mode <= MODE_PIPE;
      log_Retire_exception (rg_flog, x_rr_to_retire, rg_epc, is_interrupt, rg_cause, rg_tval);
   endrule

   // ================================================================
   // INTERFACE

   method Action init (Initial_Params initial_params);
      csrs.init (initial_params);
      rg_flog <= initial_params.flog;
   endmethod

   // Forward in
   interface fi_RR_to_Retire         = to_FIFOF_I (f_RR_to_Retire);
   interface fi_EX_Control_to_Retire = to_FIFOF_I (f_EX_Control_to_Retire);
   interface fi_EX_Int_to_Retire     = to_FIFOF_I (f_EX_Int_to_Retire);

   // Speculative DMem
   interface fi_DMem_S_rsp    = to_FIFOF_I (f_DMem_S_rsp);
   interface fo_DMem_S_commit = to_FIFOF_O (f_DMem_S_commit);

   // Non-speculative DMem
   interface fo_DMem_req = to_FIFOF_O (f_DMem_req);
   interface fi_DMem_rsp = to_FIFOF_I (f_DMem_rsp);

   // Backward out
   interface fo_Fetch_from_Retire  = to_FIFOF_O (f_Fetch_from_Retire);
   interface fo_RW_from_Retire     = to_FIFOF_O (f_RW_from_Retire);
endmodule

// ****************************************************************

endpackage
