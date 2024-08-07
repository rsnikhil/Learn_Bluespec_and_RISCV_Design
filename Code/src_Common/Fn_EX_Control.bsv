// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Fn_EX_Control;

// ****************************************************************
// EX_Control stage functionality

// ****************************************************************
// Imports from libraries

import Cur_Cycle :: *;

// ----------------
// Local imports

import Utils       :: *;
import Arch        :: *;
import Instr_Bits  :: *;
import CSR_Bits    :: *;
import Inter_Stage :: *;

// ****************************************************************

Integer verbosity = 0;

// ****************************************************************
// EX_Control: functionality

// This is actually a pure function; is ActionValue only to allow easy
// $display insertion for debugging
function ActionValue #(EX_Control_to_Retire)
         fn_EX_Control (RR_to_EX_Control  x,
			File              flog);

   actionvalue
      let instr   = x.instr;
      let rs1_val = x.rs1_val;
      let rs2_val = x.rs2_val;

      if (verbosity != 0)
	 wr_log (flog, $format ("fn_EX_Control: ", fshow_RR_to_EX_Control (x)));

      Bit #(XLEN)  next_pc   = ?;
      Bool         exception = False;    // Misaligned target_pc

      if (is_BRANCH (instr)) begin
	 Bool branch_taken = case (instr_funct3 (instr))
				funct3_BEQ:  (rs1_val == rs2_val);
				funct3_BNE:  (rs1_val != rs2_val);
				funct3_BLT:  signedLT (rs1_val, rs2_val);
				funct3_BGE:  signedGE (rs1_val, rs2_val);
				funct3_BLTU: (rs1_val < rs2_val);
				funct3_BGEU: (rs1_val >= rs2_val);
			     endcase;
	 let target_pc = x.pc + x.imm;
	 next_pc = (branch_taken ? target_pc : x.fallthru_pc);
	 exception = (branch_taken && (target_pc [1:0] != 0));
	 if (verbosity != 0) begin
	    if (branch_taken)
	       wr_log_cont (flog, $format ("    Branch taken -> %08h (exc:%0d)",
					   target_pc, exception));
	    else
	       wr_log_cont (flog, $format ("    Branch not taken (exc:%0d)", exception));
	    wr_log_cont (flog, $format ("    rs1_val:%0h rs2_val:%0h", rs1_val, rs2_val));
	 end
      end
      else if (is_JAL (instr)) begin
	 next_pc = x.pc + x.imm;
	 exception = (next_pc [1:0] != 0);
	 if (verbosity != 0)
	    wr_log_cont (flog, $format ("    JAL -> %08h (exc:%0d)",
					next_pc, exception));
      end
      else if (is_JALR (instr)) begin
	 // zero out LSB in target PC
	 next_pc = ((rs1_val + x.imm) & ~1);
	 exception = (next_pc [1:0] != 0);
	 if (verbosity != 0)
	    wr_log_cont (flog, $format ("    JAL -> %08h (exc:%0d)",
					next_pc, exception));
      end
      else begin
	 wr_log2 (flog, $format ("IMPOSSIBLE: fn_EX_Control", fshow (x)));
	 $finish (1);
      end

      let y = EX_Control_to_Retire {exception:  exception,
				    cause:      cause_INSTRUCTION_ADDRESS_MISALIGNED,
				    tval:       next_pc,
				    next_pc:    next_pc,
				    data:       x.fallthru_pc,
				    inum:       x.inum,
				    pc:         x.pc,
				    instr:      x.instr};
      return y;
   endactionvalue
endfunction

// ****************************************************************
// Logging actions

function Action log_EX_Control (File flog, RR_to_EX_Control x, EX_Control_to_Retire y);
   action
      wr_log (flog, $format ("CPU.EX_Control"));
      wr_log_cont (flog, $format ("    ", fshow_RR_to_EX_Control (x)));
      wr_log_cont (flog, $format ("    ", fshow_EX_Control_to_Retire (y)));
      ftrace (flog, x.inum, x.pc, x.instr, "EX.C", $format (""));
   endaction
endfunction

// ****************************************************************

endpackage
