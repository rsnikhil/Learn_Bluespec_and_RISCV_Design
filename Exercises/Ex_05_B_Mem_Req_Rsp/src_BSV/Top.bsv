package Top;

// ****************************************************************
// Imports from libraries

import StmtFSM :: *;
import FIFOF   :: *;

// ----------------
// Imports from 'vendor' libs

import Semi_FIFOF :: *;

// ----------------
// Local imports

import Utils        :: *;
import Instr_Bits   :: *;
import Mem_Req_Rsp  :: *;
import Mems_Devices :: *;

// ****************************************************************

(* synthesize *)
module mkTop (Empty);

   FIFOF #(Mem_Req) f_reqs <- mkFIFOF;
   FIFOF #(Mem_Rsp) f_rsps <- mkFIFOF;

   // Instantiate the memory model used by Drum and Fife.
   // We "stub out" the first five parameters and only use the last two.
   Mems_Devices_IFC mems_devices <- mkMems_Devices (// IMem interface
						    dummy_FIFOF_O,
						    dummy_FIFOF_I,

						    // Speculative DMem interace
						    dummy_FIFOF_O,
						    dummy_FIFOF_I,
						    dummy_FIFOF_O,

						    // DMem interface
						    to_FIFOF_O (f_reqs),
						    to_FIFOF_I (f_rsps));

   mkAutoFSM (
      seq
	 action
	    $display ("Initializing memory model");
	    let init_params = Initial_Params {flog: InvalidFile};
	    mems_devices.init (init_params);
	 endaction

	 action // a_req
            let mem_req = Mem_Req {req_type: funct5_LOAD,
	                           size:     MEM_4B,
				   addr:     'h_8000_0000,
				   data:     ?,
				   inum:     1,
				   pc:       'h_8000_0000,
				   instr:    ?};
	    f_reqs.enq (mem_req);
	    $display ("mem_req: ", fshow_Mem_Req (mem_req));
	 endaction

	 action // a_rsp
	    let mem_rsp = f_rsps.first;
	    f_rsps.deq;
	    // Alternative idiom to do "first" and "deq" together
	    // let mem_rsp <- pop_o (to_FIFOF_O (f_rsps));

	    $display ("mem_rsp: ", fshow_Mem_Rsp (mem_rsp, True));
	 endaction
      endseq);

endmodule

// ****************************************************************

endpackage
