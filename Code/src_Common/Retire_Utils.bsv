// Copyright (c) 2023-2024 Bluespec, Inc. All Rights Reserved.

package Retire_Utils;

// ****************************************************************
// Logging and tracing utilities for Retire step/stage
// shared by Drum and Fife

// ****************************************************************
// Imports from bsc libraries

// None

// ----------------
// Imports from 'vendor' libs

import Cur_Cycle :: *;

// ----------------
// Local imports

import Utils       :: *;
import Arch        :: *;
import Mem_Req_Rsp :: *;
import Instr_Bits  :: *;
import Inter_Stage :: *;

// ****************************************************************

function Action log_Retire_CSRRxx (File flog, Bool exc, RR_to_Retire x);
   action
      if (exc) begin
	 ftrace (flog, x.inum, x.pc, x.instr, "RET.CSRRxx.X", $format (""));
	 wr_log (flog, $format ("CPU.Retire CSRRxx EXCEPTION"));
      end
      else begin
	 ftrace (flog, x.inum, x.pc, x.instr, "RET.CSRRxx", $format (""));
	 wr_log (flog, $format ("CPU.Retire CSRRxx"));
      end
      wr_log_cont (flog, $format ("    ", fshow_RR_to_Retire (x)));
   endaction
endfunction

function Action log_Retire_MRET (File flog, RR_to_Retire x);
   action
      ftrace (flog, x.inum, x.pc, x.instr, "RET.MRET", $format (""));
      wr_log (flog, $format ("CPU.Retire MRET\n    ", fshow_RR_to_Retire (x)));
   endaction
endfunction

function Action log_Retire_ECALL_EBREAK (File flog, RR_to_Retire x);
   action
      ftrace (flog, x.inum, x.pc, x.instr, "RET.ECALL/EBREAK", $format (""));
      wr_log (flog, $format ("CPU.Retire ECALL/EBREAK\n    ", fshow_RR_to_Retire (x)));
   endaction
endfunction

function Action log_Retire_Direct_exc (File flog, RR_to_Retire x);
   action
      ftrace (flog, x.inum, x.pc, x.instr, "RET.Dir.X", $format (""));
      wr_log (flog, $format ("CPU.Retire Direct exception\n    ", fshow_RR_to_Retire (x)));
   endaction
endfunction

function Action log_Retire_Control (File                  flog,
				    Bool                  exc,
				    RR_to_Retire          x,
				    EX_Control_to_Retire  x2);
   action
      if (exc) begin
	 ftrace (flog, x.inum, x.pc, x.instr, "RET.C.X", $format (""));
	 wr_log (flog, $format ("CPU.Retire_EX_Control: Exception"));
      end
      else begin
	 ftrace (flog, x.inum, x.pc, x.instr, "RET.C", $format (""));
	 wr_log (flog, $format ("CPU.Retire_EX_Control: Normal"));
      end
      wr_log_cont (flog, $format ("    ", fshow_EX_Control_to_Retire (x2)));
   endaction
endfunction

function Action log_Retire_Int (File flog, Bool exc, RR_to_Retire x, EX_to_Retire x2);
   action
      if (exc) begin
	 ftrace (flog, x.inum, x.pc, x.instr, "RET.I.X", $format (""));
	 wr_log (flog, $format ("CPU.Retire_EX_Int: Exception"));
      end
      else begin
	 ftrace (flog, x.inum, x.pc, x.instr, "RET.I", $format (""));
	 wr_log (flog, $format ("CPU.Retire_EX_Int: Normal"));
      end
      wr_log_cont (flog, $format ("    ", fshow_EX_to_Retire (x2)));
   endaction
endfunction

function Action log_Retire_DMem (File flog, Bool exc, RR_to_Retire x, Mem_Rsp x2);
   action
      if (exc) begin
	 ftrace (flog, x.inum, x.pc, x.instr, "RET.D.X", $format (""));
	 wr_log (flog, $format ("CPU.Retire_EX_DMem: Exception"));
      end
      else begin
	 ftrace (flog, x.inum, x.pc, x.instr, "RET.D", $format (""));
	 wr_log (flog, $format ("CPU.Retire_EX_DMem: Normal"));
      end
      Bool show_data = ((x2.req_type != funct5_STORE)
			&& (x2.req_type != funct5_FENCE)
			&& (x2.req_type != funct5_FENCE_I));
      wr_log_cont (flog, $format ("    ", fshow_Mem_Rsp (x2, show_data)));
   endaction
endfunction

// Non-speculative
function Action log_DMem_NS_req (File flog, RR_to_Retire x, Mem_Req mem_req);
   action
      ftrace (flog, x.inum, x.pc, x.instr, "RET.Dreq", $format (""));
      wr_log      (flog, $format ("CPU.Retire_DMem_NS_req:"));
      wr_log_cont (flog, $format ("    ", fshow_Mem_Req (mem_req)));
   endaction
endfunction

// Non-speculative
function Action log_DMem_NS_rsp (File          flog,
				 Bool          exc,
				 RR_to_Retire  x,
				 Mem_Rsp       mem_rsp);
   action
      if (exc) begin
	 ftrace (flog, x.inum, x.pc, x.instr, "RET.Drsp.X", $format (""));
	 wr_log (flog, $format ("CPU.Retire_DMem_rsp: Exception"));
      end
      else begin
	 ftrace (flog, x.inum, x.pc, x.instr, "RET.Drsp", $format (""));
	 wr_log (flog, $format ("CPU.Retire_DMem_NS_rsp: Normal"));
      end
      Bool show_data = ((mem_rsp.req_type != funct5_STORE)
			&& (mem_rsp.req_type != funct5_FENCE)
			&& (mem_rsp.req_type != funct5_FENCE_I));
      wr_log_cont (flog, $format ("    ", fshow_Mem_Rsp (mem_rsp, show_data)));
   endaction
endfunction

function Action log_Retire_exception (File          flog,
				      RR_to_Retire  x,
				      Bit #(XLEN)   epc,
				      Bool          is_interrupt,
				      Bit #(4)      cause,
				      Bit #(XLEN)   tval);
   action
      ftrace (flog, x.inum, x.pc, x.instr, "RET.X", $format (""));
      wr_log (flog,
	      $format ("CPU.Retire_exception: epc:%0h is_interrupt:%0d cause:%0d tval%0h",
		       epc, is_interrupt, cause, tval));
   endaction
endfunction

// ****************************************************************

endpackage
