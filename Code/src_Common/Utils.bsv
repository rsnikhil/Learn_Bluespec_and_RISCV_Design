// Copyright (c) 2023-2024 Bluespec, Inc. All Rights Reserved.

package Utils;

// ****************************************************************
// Imports from bsc libraries

// None

// ----------------
// Imports from 'vendor' libs

import Cur_Cycle :: *;

// ----------------
// Local imports

import Arch        :: *;
import Mem_Req_Rsp :: *;
import Inter_Stage :: *;

// ****************************************************************
// Params passed to all modules at startup

typedef struct {
   File        flog;              // Log file
   Bit #(XLEN) pc_reset_value;
   Bit #(64)   addr_base_mem;
   Bit #(64)   size_B_mem;
   } Initial_Params
deriving (Bits);

// ****************************************************************
// Write out a trace record with standard fields then ad-hoc info

function Action ftrace (File         flog,
			Bit #(64)    inum,
			Bit #(XLEN)  pc,
			Bit #(32)    instr,
			String       label,
			Fmt          adhoc);
   action
      if (flog != InvalidFile)
	 $fdisplay (flog, "Trace %0d %0d %0h %0h %s", cur_cycle,
		    inum, pc, instr, label, adhoc);
   endaction
endfunction

// ****************************************************************
// Write out a log record to just flog, or to flog and to stdout

function Action wr_log (File  flog, Fmt fmt);
   action
      if (flog != InvalidFile) begin
	 $fwrite (flog, "%0d: ", cur_cycle);
	 $fdisplay (flog, fmt);
      end
   endaction
endfunction

// Continuation line (no cycle count)
function Action wr_log_cont (File  flog, Fmt fmt);
   action
      if (flog != InvalidFile) begin
	 $fdisplay (flog, fmt);
      end
   endaction
endfunction

// Write to logfile and to stdout
// (usually fatal error messages, before $finish)
function Action wr_log2 (File  flog, Fmt fmt);
   action
      if (flog != InvalidFile) begin
	 $fwrite (flog, "%0d: ", cur_cycle);
	 $fdisplay (flog, fmt);
      end
      $write ("%0d: ", cur_cycle);
      $display (fmt);
   endaction
endfunction

// ****************************************************************

endpackage
