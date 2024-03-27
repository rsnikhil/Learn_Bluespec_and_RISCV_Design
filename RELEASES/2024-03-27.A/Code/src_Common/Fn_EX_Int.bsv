// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Fn_EX_Int;

// ****************************************************************
// IALU: Functionality
// for LUI, AUIPC and Integer arith ops (RV32I, RV64I)
// Note: no "M" opcodes here (integer multiply/divide).

// ****************************************************************
// Imports from libraries

import Cur_Cycle :: *;

// ----------------
// Local imports

import Utils       :: *;
import Arch        :: *;
import Instr_Bits  :: *;
import CSR_Bits    :: *;    // For trap CAUSE
import IALU        :: *;
import Inter_Stage :: *;

// ****************************************************************
// EX_Int: Functionality

// This is actually a pure function; is ActionValue only to allow
// $display insertion for debugging
function ActionValue #(EX_to_Retire)
         fn_EX_Int (RR_to_EX  x,

		    File      logf);
   actionvalue
      let instr = x.instr;

      let y = EX_to_Retire {exception:  False,
			    cause:      ?,
			    tval:       ?,
			    data:       ?,
			    inum:       x.inum,
			    pc:         x.pc,
			    instr:      instr};

      if (is_LUI (instr)) begin
	 y.data = x.imm;

	 wr_log_cont (logf, $format ("fn_EX_IALU: LUI x%0d <= %0h",
				     instr_rd (instr), y.data));
      end
      else if (is_AUIPC (instr)) begin
	 y.data = x.pc + x.imm;

	 wr_log_cont (logf, $format ("fn_EX_IALU: AUIPC x%0d <= %0h",
				     instr_rd (instr), y.data));
      end
      else begin
	 let result <- fn_IALU (instr, x.rs1_val, x.rs2_val, x.imm,
				logf);

	 y.data = result;

	 wr_log_cont (logf, $format ("fn_EX_IALU: IALU x%0d <= %0h",
				     instr_rd (instr), y.data));
      end
      return y;
   endactionvalue
endfunction

// ****************************************************************
// Logging actions

function Action log_EX_Int (File flog, RR_to_EX x, EX_to_Retire y);
   action
      wr_log (flog, $format ("CPU.EX_Int"));
      wr_log_cont (flog, $format ("    ", fshow_RR_to_EX (x)));
      wr_log_cont (flog, $format ("    ", fshow_EX_to_Retire (y)));
      ftrace (flog, x.inum, x.pc, x.instr, "EX.I", $format (""));
   endaction
endfunction

// ****************************************************************

endpackage
