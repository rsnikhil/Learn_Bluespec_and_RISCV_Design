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
import Arch         :: *;
import Instr_Bits   :: *;
import Mem_Req_Rsp  :: *;
import Mems_Devices :: *;

import Inter_Stage  :: *;
import Fn_Fetch     :: *;
import Fn_Decode    :: *;
import Fn_Dispatch  :: *;
import Fn_EX_Control :: *;

// ****************************************************************

(* synthesize *)
module mkTop (Empty);

   FIFOF #(Mem_Req) f_reqs <- mkFIFOF;
   FIFOF #(Mem_Rsp) f_rsps <- mkFIFOF;

   // Register to hold Fetch-to-Decode info across time steps
   Reg #(Fetch_to_Decode) rg_F_to_D <- mkRegU;

   function Action a_req (Bit #(XLEN) pc, Bit #(64) inum);
      action
	 let predicted_pc = 0;            // Only relevant in Fife
	 let epoch        = 0;            // Only relevant in Fife
	 let flog         = InvalidFile;  // log file
	 let y <- fn_Fetch (pc, predicted_pc, epoch, inum, flog);

	 f_reqs.enq (y.mem_req);
	 // Remember Fetch-to-Decode info by storing in register
	 rg_F_to_D <= y.to_D;

	 $display ("y: ", fshow (y));
	 $display ("y.to_D: ",    fshow_Fetch_to_Decode (y.to_D));
	 $display ("y.mem_req: ", fshow_Mem_Req (y.mem_req));
      endaction
   endfunction

   function Action a_rsp (Bit #(XLEN) rs1_val, Bit #(XLEN) rs2_val);
      action
	 let mem_rsp <- pop_o (to_FIFOF_O (f_rsps));
	 $display ("mem_rsp: ", fshow_Mem_Rsp (mem_rsp, True));

	 // Get Fetch-to_Decode value remembered in register
	 let x_F_to_D = rg_F_to_D;

	 let y <- fn_Decode (x_F_to_D, mem_rsp, InvalidFile);
	 // Display using both standard and custom 'fshow'
	 $display ("fn_Decode output: ", fshow (y));
	 $display ("fn_Decode output: \n", fshow_Decode_to_RR (y));

	 let y2 <- fn_Dispatch (y, rs1_val, rs2_val, InvalidFile);
	 // Display using both standard and custom 'fshow's
	 $display ("fn_Dispatch output:\n    ", fshow (y2));
	 $display ("fn_Dispatch: to_Retire:\n",
		   fshow_RR_to_Retire (y2.to_Retire));
	 $display ("fn_Dispatch: to_EX_Control:\n",
		   fshow_RR_to_EX_Control (y2.to_EX_Control));
	 $display ("fn_Dispatch: to_EX:\n",
		   fshow_RR_to_EX (y2.to_EX));
	 $display ("fn_Dispatch: to_EX_DMem:\n",
		   fshow_Mem_Req (y2.to_EX_DMem));

	 if (y2.to_Retire.exec_tag == EXEC_TAG_CONTROL) begin
	    let y3 <- fn_EX_Control (y2.to_EX_Control, InvalidFile);
	    // Display using both standard and custom 'fshow's
	    $display ("fn_EX_Control:\n    ", fshow (y3));
	    $display ("fn_EX_Control:\n", fshow_EX_Control_to_Retire (y3));
	 end
      endaction
   endfunction

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

	 a_req ('h_8000_0000, 1);
	 a_rsp (?, ?);
	 a_req ('h_8000_003c, 2);
	 a_rsp (0, 0);
	 a_req ('h_8000_003c, 3);
	 a_rsp (0, 1);
      endseq);

endmodule

// ****************************************************************

endpackage
