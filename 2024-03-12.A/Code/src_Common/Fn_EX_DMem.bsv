// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Fn_EX_DMem;

// ****************************************************************
// DMem request and response steps

// ****************************************************************
// Imports from libraries

import Cur_Cycle :: *;

// ----------------
// Local imports

import Utils       :: *;
import Arch        :: *;
import Instr_Bits  :: *;
import CSR_Bits    :: *;
import Mem_Req_Rsp :: *;
import Inter_Stage :: *;

// ****************************************************************

Integer verbosity = 0;

// ****************************************************************
// Compute Mem_Req to send to DMem

// This is actually a pure function; is ActionValue only to allow easy
// $display insertion for debugging
function ActionValue #(Mem_Req) fn_DMem_Req (File flog, RR_to_EX  x);
   actionvalue
      // Mem effective-address calculation
      Bit #(XLEN) eaddr = x.rs1_val + x.imm;

      Mem_Req_Size mrq_size = unpack (x.instr [13:12]);  // B, H, W or D

      Mem_Req_Type mrq_type = (is_LOAD (x.instr) ? funct5_LOAD
			       : (is_STORE (x.instr) ? funct5_STORE
				  : (is_FENCE (x.instr) ? funct5_FENCE
				     : funct5_BOGUS)));

      let y = Mem_Req {inum:     x.inum,
		       pc:       x.pc,
		       instr:    x.instr,
		       req_type: mrq_type,
		       size:     mrq_size,
		       addr:     zeroExtend (eaddr),
		       data:     zeroExtend (x.rs2_val)};

      if (verbosity != 0) begin
	 wr_log (flog, $format ("    Fn_DMem: ", fshow (x)));
	 wr_log (flog, $format ("         base:%08h offset:%08h eaddr:%08h",
				x.rs1_val, x.imm, eaddr));
	 wr_log (flog, $format ("         ", fshow (y)));
      end

      return y;
   endactionvalue
endfunction

// ****************************************************************

endpackage
