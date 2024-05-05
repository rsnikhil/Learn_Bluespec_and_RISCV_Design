package Top;

// ****************************************************************
// Imports from libraries

import StmtFSM :: *;

// ----------------
// Local imports

import Instr_Bits  :: *;
import Mem_Req_Rsp :: *;

// ****************************************************************
// Imports from bsc libs

(* synthesize *)
module mkTop (Empty);

   mkAutoFSM (
      seq
	 action
            let mem_req = Mem_Req {req_type: funct5_LOAD,
	                           size:     MEM_4B,
				   addr:     'h_8000_0000,
				   data:     0,
				   inum:     ?,
				   pc:       ?,
				   instr:    ?};

	    $display ("mem_req =  ", fshow (mem_req));
	 endaction
      endseq);

endmodule

// ****************************************************************

endpackage
