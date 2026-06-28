// Copyright (c) 2023-2025 Rishiyur S. Nikhil.  All Rights Reserved.

package S5_Retire;

// ****************************************************************
// Imports from libraries

import FIFOF        :: *;
import SpecialFIFOs :: *;    // For mkPipelineFIFOF and mkBypassFIFOF
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
import CSR_Bits    :: *;    // For trap CAUSE
import Inter_Stage :: *;
import Mem_Req_Rsp :: *;

import CSRs         :: *;
import Retire_Utils :: *;

import RVFI_DII_Types :: *;    // For 'RVFI_DII_Execution' struct
import RVFI_Report    :: *;
import RVFI_BSV_to_RTL :: *;

// ****************************************************************

interface Retire_IFC;
   method Action init (Initial_Params initial_params);

   // Forward in
   interface FIFOF_I #(RR_to_Retire)          fi_RR_to_Retire;
   interface FIFOF_I #(EX_Control_to_Retire)  fi_EX_Control_to_Retire;
   interface FIFOF_I #(EX_to_Retire)          fi_EX_Int_to_Retire;

   // DMem, speculative
   interface FIFOF_I #(Mem_Rsp)               fi_DMem_S_rsp;
   interface FIFOF_O #(Retire_to_DMem_Commit) fo_DMem_S_commit;

   // DMem, non-speculative
   interface FIFOF_O #(Mem_Req)  fo_DMem_req;
   interface FIFOF_I #(Mem_Rsp)  fi_DMem_rsp;

   // Backward out
   interface FIFOF_O #(Fetch_from_Retire)  fo_Fetch_from_Retire;
   interface FIFOF_O #(RW_from_Retire)     fo_RW_from_Retire;

   // Set TIME
   (* always_ready, always_enabled *)
   method Action set_TIME (Bit #(64) t);

   // Set MIP.MTIP
   (* always_ready, always_enabled *)
   method Action set_MIP_MTIP (Bit #(1) v);

   // ----------------------------------------------------------------
   // Output stream of RVFI reports (to verifier/logger)

   // OLD: interface FIFOF_O #(RVFI_DII_Execution #(XLEN, 64)) fo_rvfi_reports;

   interface RVFI_RTL_M_IFC #(XLEN, 64) rvfi_RTL_ports;

   // ----------------------------------------------------------------
   // Debugger control
   // For haltreq/resumereq, True result means OK, False means error
   method ActionValue #(Bool) haltreq;
   method ActionValue #(Bool) resumereq;

   method Bool is_running;
   method Bool is_halted;

   method ActionValue #(Bool)
          csr_write (Bit #(12) csr_addr, Bit #(XLEN) csr_val);
   method ActionValue #(Tuple2 #(Bool, Bit #(XLEN)))
          csr_read (Bit #(12) csr_addr);
endinterface

// ****************************************************************

typedef enum {MODE_PIPE,        // Normal pipeline operation
	      MODE_DMEM_RSP,    // Handle Non-speculative DMem response
	      MODE_EXCEPTION
} Module_Mode
deriving (Bits, Eq, FShow);

// Debugger control
typedef enum {S5_RUNNING,
              S5_HALTREQ,
              S5_HALTING1,
              S5_HALTING2,
              S5_HALTED
} S5_RunState
deriving (Bits, Eq, FShow);

Integer verbosity = 0;

// ****************************************************************

(* synthesize *)
module mkRetire (Retire_IFC);
   Reg #(File) rg_flog <- mkReg (InvalidFile);    // debugging

   // Control-and-Status Registers (CSRs)
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

   // Debugger control
   Reg #(S5_RunState) rg_runstate     <- mkReg (S5_RUNNING);
   Reg #(Bit #(XLEN)) rg_dpc          <- mkRegU;
   Reg #(Bit #(3))    rg_dcsr_cause   <- mkRegU;
   Reg #(Bit #(2))    rg_dcsr_prv     <- mkRegU;

   Bit #(32) dpc  = csrs.get_dpc;
   Bit #(32) dcsr = csrs.get_dcsr;

   // TODO (IMPROVEMENT) 'ebreak_halt' only depends on dcsr.ebreakm
   // while only supporting M priv. For M+U, M+S+U, M+VS+VU+U also
   // depends on other dcsr ebreak bits
   Bool ebreak_halt = (dcsr [index_dcsr_ebreakm] == 1'b1);

   // ****************************************************************
   // RVFI reporting

   RVFI_Report_IFC rvfi_report <- mkRVFI_Report;

   // Transactor from BSV RVFI struct to RTL buses

   RVFI_BSV_to_RTL_IFC #(XLEN, 64) rvfi_BSV_to_RTL <- mkRVFI_BSV_to_RTL;

   mkConnection (rvfi_report.fo_rvfi_reports, rvfi_BSV_to_RTL.fi_rvfi_reports);

   // ****************************************************************
   // BEHAVIOR

   // ================================================================
   // Functions for actions used in many rules


   function Action fa_redirect_Fetch (Bool         mispredicted,
				      Bool         haltreq,
				      RR_to_Retire x1,
				      Bit #(XLEN)  next_pc);
      action

	 if (haltreq) begin
	    rg_dpc        <= next_pc;
	    rg_dcsr_prv   <= priv_M;
	    rg_runstate   <= S5_HALTING1;
	    if (verbosity != 0)
	       $display ("S5_Retire.fa_redirect_Fetch: rg_runstate: HALTREQ->HALTING1");
	 end

	 if (((rg_runstate == S5_RUNNING) && mispredicted)
	     || haltreq)
	    begin
	       let next_epoch = rg_epoch + 1;
	       rg_epoch <= next_epoch;
	       let y = Fetch_from_Retire {next_pc:    next_pc,
					  next_epoch: next_epoch,
					  haltreq:    haltreq,
					  xtra: Fetch_from_Retire_Xtra {
					     inum:  x1.xtra.inum,
					     pc:    x1.pc,
					     instr: x1.instr}
					  };
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
				    xtra: RW_from_Retire_Xtra {
				       inum:       x1.xtra.inum,
				       pc:         x1.pc,
				       instr:      x1.instr}
				    };
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
					  inum: x1.xtra.inum};

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

   // Interrupt
   //     Tuple2 #(Bool, Bit #(4))
   match { .can_take_intr, .intr_cause } = csrs.can_take_interrupt;
   Bool take_interrupt = ((rg_mode == MODE_PIPE) && (! wrong_path) && can_take_intr);

   // Conditions for retiring non-wrong-path instructions
   Bool retire_PIPE             = ((rg_mode == MODE_PIPE) && (! wrong_path) && (! can_take_intr));
   Bool retire_Direct           = (retire_PIPE && is_Direct && (! x_rr_to_retire.exception));
   Bool retire_Direct_Exception = (retire_PIPE && is_Direct && x_rr_to_retire.exception);
   Bool retire_Control          = (retire_PIPE && is_Control);
   Bool retire_Int              = (retire_PIPE && is_Int);
   Bool retire_DMem             = (retire_PIPE && is_DMem);

   // ================================================================
   // Take interrupt (MODE_PIPE; not wrong-path; can take interrupt)

   rule rl_take_intr (take_interrupt);
      Bool        is_interrupt = True;
      Bit #(XLEN) tval         = 0;
      Bit #(XLEN) tvec_pc <- csrs.mav_exception (x_rr_to_retire.pc,
						 is_interrupt,
						 intr_cause,
						 tval);
      Bool mispredicted = True;
      Bool is_Halt_Req  = False;
      fa_redirect_Fetch (mispredicted, is_Halt_Req, x_rr_to_retire, tvec_pc);

      log_Retire_exception (rg_flog, x_rr_to_retire,
			    x_rr_to_retire.pc, is_interrupt, intr_cause, tval);
   endrule

   // ================================================================
   // Wrong-path; ignore and discard (all pipes)

   rule rl_Retire_wrong_path ((rg_mode == MODE_PIPE)
			      && wrong_path
			      && (! x_rr_to_retire.halt_sentinel));
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
      ftrace (rg_flog, x_rr_to_retire.xtra.inum, x_rr_to_retire.pc, x_rr_to_retire.instr,
	      "RET.discard", $format (""));
      wr_log (rg_flog, $format ("CPU.S5.rl_Retire_wrong_path:\n    ",
				+ fshow_RR_to_Retire (x_rr_to_retire)));
   endrule

   // ================================================================
   // Halting for debugger

   rule rl_Retire_wrong_path_halt1 (rg_runstate == S5_HALTING1);
      csrs.save_dpc_dcsr_cause_prv (rg_dpc, rg_dcsr_cause, rg_dcsr_prv);
      rg_runstate <= S5_HALTING2;

      if (verbosity != 0)
	 $display ("S5_Retire: saving DPC %0h DCSR.cause %0d DCSR.prv %0d",
		   rg_dpc, rg_dcsr_cause, rg_dcsr_prv);
   endrule

   rule rl_Retire_wrong_path_halt2 ((rg_mode == MODE_PIPE)
				    && wrong_path
				    && (rg_runstate == S5_HALTING2)
				    && x_rr_to_retire.halt_sentinel);
      f_RR_to_Retire.deq;
      rg_runstate <= S5_HALTED;

      if (verbosity != 0)
	 $display ("CPU.S5: received halt_sentinel from S3_RR");
      $display ("CPU.S5: HALTED");
   endrule

   // ================================================================
   // Retire RR Direct

   // ----------------
   // RR direct: CSRRxx

   rule rl_Retire_CSRRxx (retire_Direct
			  && is_legal_CSRRxx (x_rr_to_retire.instr));
      // Note: mav_csrrxx takes care of csrs.ma_incr_instret as well
      match { .exc, .rd_val } <- csrs.mav_csrrxx (x_rr_to_retire.instr,
						  x_rr_to_retire.rs1_val);
      // Unreserve/commit rd if needed
      fa_update_rd (x_rr_to_retire, (! exc), rd_val);

      if (! exc) begin
	 f_RR_to_Retire.deq;

	 Bool mispredicted = (x_rr_to_retire.predicted_pc
			      != x_rr_to_retire.fallthru_pc);
	 fa_redirect_Fetch (mispredicted,
			    (rg_runstate == S5_HALTREQ),
			    x_rr_to_retire,
			    x_rr_to_retire.fallthru_pc);
	 let epoch = (mispredicted ? rg_epoch + 1 : rg_epoch);
	 rvfi_report.rvfi_CSRRxx (x_rr_to_retire,
				  rd_val,
				  csrs.mv_instret,
				  epoch);
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

   rule rl_Retire_MRET (retire_Direct
			&& is_legal_MRET (x_rr_to_retire.instr));
      f_RR_to_Retire.deq;
      let new_pc <- csrs.mav_xRET;
      Bool mispredicted = True;
      fa_redirect_Fetch (mispredicted,
			 (rg_runstate == S5_HALTREQ),
			 x_rr_to_retire,
			 new_pc);
      csrs.ma_incr_instret;

      let epoch = (mispredicted ? rg_epoch + 1 : rg_epoch);
      rvfi_report.rvfi_MRET (x_rr_to_retire, new_pc, csrs.mv_instret, epoch);
      log_Retire_MRET (rg_flog, x_rr_to_retire);
   endrule

   // ----------------
   // RR direct: ECALL/EBREAK

   rule rl_Retire_ECALL_EBREAK (retire_Direct
				&& (is_legal_ECALL (x_rr_to_retire.instr)
				    || (is_legal_EBREAK (x_rr_to_retire.instr)
					&& (! ebreak_halt))));
      rg_epc   <= x_rr_to_retire.pc;
      rg_cause <= ((x_rr_to_retire.instr [20] == 0)
		   ? cause_ECALL_FROM_M
		   : cause_BREAKPOINT);
      rg_tval  <= 0;
      csrs.ma_incr_instret;
      rg_mode <= MODE_EXCEPTION;

      log_Retire_ECALL_EBREAK (rg_flog, x_rr_to_retire);
   endrule

   // ----------------
   // RR direct: EBREAK debug-halt

   rule rl_Retire_EBREAK_dbg_halt (retire_Direct
				   && is_legal_EBREAK (x_rr_to_retire.instr)
				   && ebreak_halt);
      f_RR_to_Retire.deq;
      Bool mispredicted   = False;
      Bool haltreq        = True;
      // On debug-halt, set next_pc to this PC
      // so this instr will be retried on resume
      Bit #(XLEN) next_pc = x_rr_to_retire.pc;
      // 'fa_redirect_Fetch()' Will set rg_runstate to S5_HALTING1
      fa_redirect_Fetch (mispredicted, haltreq, x_rr_to_retire, next_pc);
      $display ("CPU.S5: Halting on EBREAK");
   endrule

   // ----------------
   // RR direct; exception

   rule rl_Retire_Direct_exception (retire_Direct_Exception);
      rg_epc   <= x_rr_to_retire.pc;
      rg_cause <= x_rr_to_retire.cause;
      rg_tval  <= x_rr_to_retire.tval;
      rg_mode <= MODE_EXCEPTION;

      log_Retire_Direct_exc (rg_flog, x_rr_to_retire);

      /*
      if (x_rr_to_retire.cause == cause_ILLEGAL_INSTRUCTION) begin
	 wr_log2 (rg_flog,
		  $format ("    TEMPORARY SIM OPTION: FINISH ON ILLEGAL INSTR"));
	 $finish (1);
      end
      */

   endrule

   // ================================================================
   // Retire EX_Control pipe

   rule rl_Retire_EX_Control (retire_Control);
      let x2 <- pop_o (to_FIFOF_O (f_EX_Control_to_Retire));

      // Unreserve/commit rd if needed
      fa_update_rd (x_rr_to_retire, (! x2.exception), x2.data);

      if (! x2.exception) begin
	 f_RR_to_Retire.deq;

	 // Redirect Fetch PC if mispredicted
	 Bool mispredicted = (x_rr_to_retire.predicted_pc != x2.next_pc);
	 fa_redirect_Fetch (mispredicted,
			    (rg_runstate == S5_HALTREQ),
			    x_rr_to_retire,
			    x2.next_pc);
	 csrs.ma_incr_instret;
	 let epoch = (mispredicted ? rg_epoch + 1 : rg_epoch);
	 rvfi_report.rvfi_Control (x_rr_to_retire, x2, csrs.mv_instret, epoch);
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

   rule rl_Retire_EX_Int (retire_Int);
      EX_to_Retire x2 <- pop_o (to_FIFOF_O (f_EX_Int_to_Retire));

      // Unreserve/commit rd if needed
      fa_update_rd (x_rr_to_retire, (! x2.exception), x2.data);

      if (! x2.exception) begin
	 f_RR_to_Retire.deq;

	 // Redirect Fetch PC if mispredicted
	 Bool mispredicted = (x_rr_to_retire.predicted_pc
			      != x_rr_to_retire.fallthru_pc);
	 fa_redirect_Fetch (mispredicted,
			    (rg_runstate == S5_HALTREQ),
			    x_rr_to_retire,
			    x_rr_to_retire.fallthru_pc);
	 csrs.ma_incr_instret;
	 let epoch = (mispredicted ? rg_epoch + 1 : rg_epoch);
	 rvfi_report.rvfi_Int (x_rr_to_retire,
			       x2,
			       csrs.mv_instret,
			       epoch);
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

   rule rl_Retire_EX_DMem (retire_DMem
			   && (f_DMem_S_rsp.first.rsp_type != MEM_REQ_DEFERRED));

      let x2 <- pop_o (to_FIFOF_O (f_DMem_S_rsp));

      Bool exception = (x2.rsp_type != MEM_RSP_OK);

      // Sign-extend data if necessary
      Bit #(XLEN) rd_val = 0;
      if ((instr_opcode (x_rr_to_retire.instr) == opcode_LOAD)
	  && (instr_rd (x_rr_to_retire.instr) != 0))
	 begin
	    rd_val = truncate (x2.data);
	    if (instr_funct3 (x_rr_to_retire.instr) == funct3_LB)
	       rd_val = signExtend (rd_val [7:0]);
	    else if (instr_funct3 (x_rr_to_retire.instr) == funct3_LBU)
	       rd_val = zeroExtend (rd_val [7:0]);
	    else if (instr_funct3 (x_rr_to_retire.instr) == funct3_LH)
	       rd_val = signExtend (rd_val [15:0]);
	    else if (instr_funct3 (x_rr_to_retire.instr) == funct3_LHU)
	       rd_val = zeroExtend (rd_val [15:0]);
	    // TODO: LW in RV64
	 end

      // Unreserve/commit rd if needed
      fa_update_rd (x_rr_to_retire, (! exception), rd_val);

      if (! exception) begin
	 f_RR_to_Retire.deq;

	 // Send 'commit' (True) to store-buf, if needed
	 fa_retire_store_buf (x_rr_to_retire, x2, True);

	 // Redirect Fetch PC if mispredicted
	 Bool mispredicted = (x_rr_to_retire.predicted_pc
			      != x_rr_to_retire.fallthru_pc);
	 fa_redirect_Fetch (mispredicted,
			    (rg_runstate == S5_HALTREQ),
			    x_rr_to_retire,
			    x_rr_to_retire.fallthru_pc);
	 csrs.ma_incr_instret;

	 let epoch = (mispredicted ? rg_epoch + 1 : rg_epoch);
	 rvfi_report.rvfi_DMem (x_rr_to_retire,
				x2, rd_val,
				csrs.mv_instret,
				epoch);
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

   rule rl_Retire_DMem_deferred (retire_DMem
				 && (f_DMem_S_rsp.first.rsp_type == MEM_REQ_DEFERRED));
      let x2 <- pop_o (to_FIFOF_O (f_DMem_S_rsp));

      // Issue DMem request
      let mem_req = Mem_Req {req_type: x2.req_type,
			     size:     x2.size,
			     addr:     x2.addr,
			     data:     x2.data,
			     xtra: Mem_Req_Xtra {
				inum:   x2.xtra.inum,
				pc:     x2.xtra.pc,
				instr:  x2.xtra.instr}
			     };
      f_DMem_req.enq (mem_req);
      rg_mode <= MODE_DMEM_RSP;    // go to await response

      log_DMem_NS_req (rg_flog, x_rr_to_retire, mem_req);
   endrule

   // ----------------------------------------------------------------
   // Handle DMem response

   rule rl_Retire_DMem_rsp (rg_mode == MODE_DMEM_RSP);
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

	 // Unreserve rd if needed
	 fa_update_rd (x_rr_to_retire, False, ?);
      end
      else if (x2.rsp_type == MEM_REQ_DEFERRED) begin
	 wr_log2 (rg_flog, ($format ("INTERNAL_ERROR: CPU.rl_Retire_DMem_rsp:")
			    + $format ("\n    ", fshow_Mem_Rsp (x2, True))
			    + $format ("\n    Unexpected MEM_REQ_DEFERRED; QUIT.")));

	 // IMPOSSIBLE. Non-speculative requests cannot be deferred
	 $finish (1);
      end
      else begin
	 f_RR_to_Retire.deq;

	 // Sign-extend data if necessary
	 Bit #(XLEN) rd_val = truncate (x2.data);
	 if ((instr_opcode (x_rr_to_retire.instr) == opcode_LOAD)
	     && (instr_rd (x_rr_to_retire.instr) != 0))
	    begin
	       if (instr_funct3 (x_rr_to_retire.instr) == funct3_LB)
		  rd_val = signExtend (rd_val [7:0]);
	       else if (instr_funct3 (x_rr_to_retire.instr) == funct3_LBU)
		  rd_val = zeroExtend (rd_val [7:0]);
	       else if (instr_funct3 (x_rr_to_retire.instr) == funct3_LH)
		  rd_val = signExtend (rd_val [15:0]);
	       else if (instr_funct3 (x_rr_to_retire.instr) == funct3_LHU)
		  rd_val = zeroExtend (rd_val [15:0]);
	       // TODO: LW in RV64
	    end

	 // Unreserve/commit rd if needed
	 fa_update_rd (x_rr_to_retire, True, rd_val);

	 // Redirect Fetch to correct mispredicted PC
	 Bool mispredicted = (x_rr_to_retire.predicted_pc
			      != x_rr_to_retire.fallthru_pc);
	 fa_redirect_Fetch (mispredicted,
			    (rg_runstate == S5_HALTREQ),
			    x_rr_to_retire,
			    x_rr_to_retire.fallthru_pc);
	 csrs.ma_incr_instret;

	 let epoch = (mispredicted ? rg_epoch + 1 : rg_epoch);
	 rvfi_report.rvfi_DMem (x_rr_to_retire,
				x2,
				rd_val,
				csrs.mv_instret,
				epoch);

	 // Resume pipeline behavior
	 rg_mode <= MODE_PIPE;
      end

      log_DMem_NS_rsp (rg_flog, exception, x_rr_to_retire, x2);
   endrule

   // ================================================================
   // All exceptions

   rule rl_exception (rg_mode == MODE_EXCEPTION);
      f_RR_to_Retire.deq;

      Bool is_interrupt = False;
      Bit #(XLEN) tvec_pc <- csrs.mav_exception (rg_epc,
						 is_interrupt,
						 rg_cause,
						 rg_tval);
      Bool mispredicted = True;
      fa_redirect_Fetch (mispredicted,
			 (rg_runstate == S5_HALTREQ),
			 x_rr_to_retire,
			 tvec_pc);
      rg_mode <= MODE_PIPE;

      rvfi_report.rvfi_Exception (x_rr_to_retire,
				  tvec_pc,
				  csrs.mv_instret,
				  rg_epoch + 1);
      log_Retire_exception (rg_flog,
			    x_rr_to_retire,
			    rg_epc,
			    is_interrupt,
			    rg_cause,
			    rg_tval);
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

   // DMem, speculative
   interface fi_DMem_S_rsp    = to_FIFOF_I (f_DMem_S_rsp);
   interface fo_DMem_S_commit = to_FIFOF_O (f_DMem_S_commit);

   // DMem, non-speculative
   interface fo_DMem_req = to_FIFOF_O (f_DMem_req);
   interface fi_DMem_rsp = to_FIFOF_I (f_DMem_rsp);

   // Backward out
   interface fo_Fetch_from_Retire  = to_FIFOF_O (f_Fetch_from_Retire);
   interface fo_RW_from_Retire     = to_FIFOF_O (f_RW_from_Retire);

   // Set TIME
   method Action set_TIME (Bit #(64) t) = csrs.set_TIME (t);


   // Set MIP.MTIP
   method Action set_MIP_MTIP (Bit #(1) v) = csrs.set_MIP_MTIP (v);

   // ----------------------------------------------------------------
   // Output stream of RVFI reports (to verifier/logger)

   // OLD: interface FIFOF_O fo_rvfi_reports = rvfi_report.fo_rvfi_reports;

   interface rvfi_RTL_ports = rvfi_BSV_to_RTL.rvfi_RTL_ports;

   // ----------------------------------------------------------------
   // Debugger control
   // For haltreq/resumereq, True result means OK, False means error

   method ActionValue #(Bool) haltreq;
      Bool result = False;
      if (rg_runstate == S5_RUNNING) begin
	 rg_runstate   <= S5_HALTREQ;
	 rg_dcsr_cause <= dcsr_cause_haltreq;
	 result = True;
	 $display ("CPU.S5: halt request from debugger");
      end
      return result;
   endmethod

   method ActionValue #(Bool) resumereq;
      Bool result = False;
      if (rg_runstate == S5_HALTED) begin
	 Bit #(1) step = dcsr [index_dcsr_step];
	 Bit #(2) prv  = dcsr [index_dcsr_prv + 1: index_dcsr_prv];

	 let y = Fetch_from_Retire {next_pc:    dpc,
				    next_epoch: rg_epoch,
				    haltreq:    False,
				    xtra: Fetch_from_Retire_Xtra {
				       inum:  ?,
				       pc:    ?,
				       instr: ?}
				    };
	 f_Fetch_from_Retire.enq (y);


	 if (step == 1'b0) begin
	    $display ("CPU.S5: resume request from debugger: RUNNING");
	    rg_runstate   <= S5_RUNNING;
	    // Note, dcsr_cause_ebreak may be overridden by dcsr_cause_haltreq
	    rg_dcsr_cause <= dcsr_cause_ebreak;
	 end
	 else begin
	    $display ("CPU.S5: resume request from debugger: SINGLE STEP");
	    rg_runstate   <= S5_HALTREQ;
	    rg_dcsr_cause <= dcsr_cause_step;
	 end

	 result = True;
	 if (verbosity != 0)
	    $display ("S5_Retire.method resumereq: PC %0h epoch %0d prv %0d step %0d",
		      dpc, rg_epoch, prv, step);
      end
      return result;
   endmethod

   method Bool is_running = (rg_runstate != S5_HALTED);
   method Bool is_halted  = (rg_runstate == S5_HALTED);

   method ActionValue #(Bool) csr_write (Bit #(12) csr_addr, Bit #(XLEN) csr_val);
      Bool result = False;
      if (rg_runstate == S5_HALTED) begin
	 let b <- csrs.csr_write (csr_addr, csr_val);
	 result = b;
      end
      return  result;
   endmethod

   method ActionValue #(Tuple2 #(Bool, Bit #(XLEN))) csr_read (Bit #(12) csr_addr);
      if (rg_runstate == S5_HALTED) begin
	 let t2 <- csrs.csr_read (csr_addr);
	 return t2;
      end
      else
	 return  tuple2 (False, ?);
   endmethod
endmodule

// ****************************************************************

endpackage
