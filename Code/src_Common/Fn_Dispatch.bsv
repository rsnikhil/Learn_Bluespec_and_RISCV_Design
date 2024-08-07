// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Fn_Dispatch;

// ****************************************************************
// Register-Read and Dispatch step

// ****************************************************************
// Imports from libraries

import Cur_Cycle :: *;

// ----------------
// Local imports

import Utils       :: *;
import Arch        :: *;
import Instr_Bits  :: *;
import Mem_Req_Rsp :: *;
import Inter_Stage :: *;

// ****************************************************************

Integer verbosity = 0;

// ****************************************************************
// Register-read dispatch to execute steps

typedef struct {
   RR_to_Retire      to_Retire;
   RR_to_EX_Control  to_EX_Control;
   RR_to_EX          to_EX;
   Mem_Req           to_EX_DMem;
} Result_Dispatch
deriving (Bits, FShow);

// This is actually a pure function; is ActionValue only to allow easy
// $display insertion for debugging
function ActionValue #(Result_Dispatch)
         fn_Dispatch (Decode_to_RR         x,
		      Bit #(XLEN)          rs1_val,
		      Bit #(XLEN)          rs2_val,

		      File                 flog);
   actionvalue
      // Compute tag to control merging at Retire
      Exec_Tag exec_tag = EXEC_TAG_DIRECT;    // exceptions and OPCLASS_SYSTEM
      if (! x.exception) begin
	 if      (x.opclass == OPCLASS_CONTROL) exec_tag = EXEC_TAG_CONTROL;
	 else if (x.opclass == OPCLASS_INT)     exec_tag = EXEC_TAG_INT;
	 else if (x.opclass == OPCLASS_MEM)     exec_tag = EXEC_TAG_DMEM;
	 else if (x.opclass == OPCLASS_FENCE)   exec_tag = EXEC_TAG_DMEM;
      end

      let to_Retire = RR_to_Retire {exec_tag:     exec_tag,

				    pc:           x.pc,
				    has_rd:       x.has_rd,
				    writes_mem:   x.writes_mem,

				    exception:    x.exception,
				    cause:        x.cause,
				    tval:         x.tval,

				    instr:        x.instr,
				    fallthru_pc:  x.fallthru_pc,
				    rs1_val:      rs1_val,

				    predicted_pc: x.predicted_pc,
				    epoch:        x.epoch,
				    inum:         x.inum};

      // ----------------
      // Info for EX_Control
      let to_EX_Control = RR_to_EX_Control {pc:           x.pc,
					    fallthru_pc:  x.fallthru_pc,
					    instr:        x.instr,
					    rs1_val:      rs1_val,
					    rs2_val:      rs2_val,
					    imm:          x.imm,
					    inum:         x.inum};

      // ----------------
      // Info for Execute Int pipe
      let to_EX  = RR_to_EX {pc:      x.pc,
			     instr:   x.instr,
			     rs1_val: rs1_val,
			     rs2_val: rs2_val,
			     imm:     x.imm,
			     inum:    x.inum};

      // ----------------
      // Info for Execute DMem pipe
      Bit #(XLEN)  eaddr    = rs1_val + x.imm;
      Mem_Req_Size mrq_size = unpack (x.instr [13:12]);  // B, H, W or D
      Mem_Req_Type mrq_type = (is_LOAD (x.instr) ? funct5_LOAD
			       : (is_STORE (x.instr) ? funct5_STORE
				  : (is_FENCE (x.instr) ? funct5_FENCE
				     : (is_FENCE_I (x.instr) ? funct5_FENCE_I
					: funct5_BOGUS))));

      let to_EX_DMem = Mem_Req {req_type: mrq_type,
				size:     mrq_size,
				addr:     zeroExtend (eaddr),
				data:     zeroExtend (rs2_val),

				inum:     x.inum,
				pc:       x.pc,
				instr:    x.instr};

      // ----------------
      // Construct and return final result
      let result = Result_Dispatch {to_Retire:     to_Retire,
				    to_EX_Control: to_EX_Control,
				    to_EX:         to_EX,
				    to_EX_DMem:    to_EX_DMem};
      return result;
   endactionvalue
endfunction

// ****************************************************************
// Logging actions

function Action log_Dispatch_Direct (File flog, RR_to_Retire x);
   action
      wr_log (flog, $format ("CPU.Dispatch_Direct:"));
      wr_log_cont (flog, $format ("    ", fshow_RR_to_Retire (x)));
      ftrace (flog, x.inum, x.pc, x.instr, "RR.dir", $format (""));
   endaction
endfunction

function Action log_Dispatch_Control (File flog, RR_to_Retire x, RR_to_EX_Control y);
   action
      wr_log (flog, $format ("CPU.Dispatch_Control:"));
      wr_log_cont (flog, $format ("    ", fshow_RR_to_Retire (x)));
      wr_log_cont (flog, $format ("    ", fshow_RR_to_EX_Control (y)));
      ftrace (flog, x.inum, x.pc, x.instr, "RR.C", $format (""));
   endaction
endfunction

function Action log_Dispatch_Int (File flog, RR_to_Retire x, RR_to_EX y);
   action
      wr_log (flog, $format ("CPU.Dispatch_Int:"));
      wr_log_cont (flog, $format ("    ", fshow_RR_to_Retire (x)));
      wr_log_cont (flog, $format ("    ", fshow_RR_to_EX (y)));
      ftrace (flog, x.inum, x.pc, x.instr, "RR.I", $format (""));
   endaction
endfunction

function Action log_Dispatch_DMem (File flog, RR_to_Retire x, RR_to_EX y, Mem_Req mem_req);
   action
      wr_log (flog, $format ("CPU.Dispatch_DMem:"));
      wr_log_cont (flog, $format ("    ", fshow_RR_to_Retire (x)));
      wr_log_cont (flog, $format ("        rs1_val:%08h  rs2_val:%08h  imm:%08h",
				  y.rs1_val, y.rs2_val, y.imm));
      wr_log_cont (flog, $format ("    ", fshow_Mem_Req (mem_req)));
      ftrace (flog, x.inum, x.pc, x.instr, "RR.D", $format (""));
   endaction
endfunction

// ****************************************************************

endpackage
