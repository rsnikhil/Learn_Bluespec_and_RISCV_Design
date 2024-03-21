// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Mem_Req_Rsp;

// ****************************************************************

import Arch       :: *;
import Instr_Bits :: *;

// ****************************************************************
// Memory requests

// See Instr_Bits for funct5 codes for LOAD/STORE/AMOs
// (we use original funct5s for AMOs, and add two more codes for LOAD/STORE)
typedef Bit #(5) Mem_Req_Type;

function Fmt fshow_Mem_Req_Type (Mem_Req_Type mrt);
   return case (mrt)
	     funct5_LOAD:    $format ("LOAD");
	     funct5_STORE:   $format ("STORE");
	     funct5_FENCE:   $format ("FENCE");

	     funct5_LR:      $format ("LR");
	     funct5_SC:      $format ("SC");
	     funct5_AMOSWAP: $format ("AMOSWAP");
	     funct5_AMOADD:  $format ("AMOADD");
	     funct5_AMOXOR:  $format ("AMOXOR");
	     funct5_AMOAND:  $format ("AMOAND");
	     funct5_AMOOR:   $format ("AMOOR");
	     funct5_AMOMIN:  $format ("AMOMIN");
	     funct5_AMOMAX:  $format ("AMOMAX");
	     funct5_AMOMINU: $format ("AMOMINU");
	     funct5_AMOMAXU: $format ("AMOMAXU");
	     default:	     $format ("<unknown Mem_Req_Type %0h", mrt);
	  endcase;
endfunction

typedef enum {MEM_1B, MEM_2B, MEM_4B, MEM_8B} Mem_Req_Size
deriving (Eq, FShow, Bits);

typedef struct {Mem_Req_Type  req_type;
		Mem_Req_Size  size;
		Bit #(64)     addr;
		Bit #(64)     data;     // CPU => mem data

		Bit #(64)     inum;     // for debugging only
		Bit #(XLEN)   pc;       // for debugging only
		Bit #(32)     instr;
} Mem_Req
deriving (Eq, FShow, Bits);

// ****************************************************************
// Memory responses

typedef enum {MEM_RSP_OK,
	      MEM_RSP_MISALIGNED,
	      MEM_RSP_ERR,

	      MEM_REQ_DEFERRED    // DMem only, for accesses that must be non-speculative

} Mem_Rsp_Type
deriving (Eq, FShow, Bits);

typedef struct {Mem_Rsp_Type  rsp_type;
		Bit #(64)     data;      // mem => CPU data

		// Copied from mem_req, for debugging only
		Mem_Req_Type  req_type;
		Mem_Req_Size  size;
		Bit #(64)     addr;

		Bit #(64)     inum;     // for debugging only
		Bit #(XLEN)   pc;       // for debugging only
		Bit #(32)     instr;
} Mem_Rsp
deriving (Eq, FShow, Bits);

// ****************************************************************
// Alternate fshow functions

function Fmt fshow_Mem_Req_Size (Mem_Req_Size x);
   let fmt = case (x)
		MEM_1B: $format ("1B");
		MEM_2B: $format ("2B");
		MEM_4B: $format ("4B");
		MEM_8B: $format ("8B");
	     endcase;
   return fmt;
endfunction

function Fmt fshow_Mem_Req (Mem_Req x);
   let fmt = $format ("    Mem_Req {I_%0d pc:%08h instr:%08h ", x.inum, x.pc, x.instr);
   fmt = fmt + fshow_Mem_Req_Type (x.req_type);
   fmt = fmt + $format (" ");
   fmt = fmt + fshow_Mem_Req_Size (x.size);
   fmt = fmt + $format (" a:%08h", x.addr);
   if ((x.req_type != funct5_LOAD)
       && (x.req_type != funct5_LR)
       && (x.req_type != funct5_FENCE))
      fmt = fmt + $format (" data:%08h", x.data);
   fmt = fmt + $format ("}");
   return fmt;
endfunction

function Fmt fshow_Mem_Rsp (Mem_Rsp x, Bool show_data);
   let fmt = $format ("    Mem_Rsp {I_%0d pc:%08h instr:%08h ", x.inum, x.pc, x.instr);
   fmt = fmt + fshow (x.rsp_type);
   if (show_data)
      fmt = fmt + $format (" d:%08h", x.data);
   fmt = fmt + $format ("}");
   return fmt;
endfunction

// ****************************************************************

endpackage
