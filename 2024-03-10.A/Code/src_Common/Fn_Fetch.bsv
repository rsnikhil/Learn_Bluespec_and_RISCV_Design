// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Fn_Fetch;

// ****************************************************************
// Fetch stage

// ****************************************************************
// Imports from libraries

// None

// ----------------
// Local imports

import Arch        :: *;
import Instr_Bits  :: *;
import Mem_Req_Rsp :: *;
import Inter_Stage :: *;

// ****************************************************************
// Fetch: Functionality

typedef struct {
   Fetch_to_Decode   to_D;
   Mem_Req  mem_req;
} Result_F
deriving (Bits, FShow);


// This is actually a pure function; is ActionValue only to allow
// $display insertion for debugging
function ActionValue #(Result_F)
         fn_Fetch (Bit #(XLEN)  pc,
		   Bit #(XLEN)  predicted_pc,
		   Epoch        epoch,
		   Bit #(64)    inum,
		   File         flog);

   actionvalue
      Result_F y = ?;
      // Info to next stage
      y.to_D = Fetch_to_Decode {pc:           pc,
				predicted_pc: predicted_pc,
				epoch:        epoch,
				inum:         inum};
      // Request to IMem
      y.mem_req = Mem_Req {req_type: funct5_LOAD,
			   size:     MEM_4B,
			   addr:     zeroExtend (pc),
			   data :    ?,
			   // Debugging
			   inum:     inum,
			   pc:       pc,
			   instr:    ?};
      return y;
   endactionvalue
endfunction

// ****************************************************************

endpackage
