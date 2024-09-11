// Copyright (c) 2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Store_Buffer;

// ****************************************************************
// This package implements a store-buffer (a searchable queue).
//   MMIO and misaligned requests immediately return DEFERRED response.
//   Store requests from CPU are enqueued; response to CPU is immediate
//   Commit/discard requests discard the head of the queue
//                and if 'commit', then also writes to memory
//   Load requests use memory-read as baseline, then update from
//                store-buffer if any matches.

// Each STORE must be buffered separately even if they have
// overlapping addresses because their commits/discards may be
// different.


// TODO: Add AMOs.  Subtlety: suppose we did speculative partial-word
//       STOREs (so, several store-buffer entries),
//       Then, a speculative AMO: load_via_sb, then add new val to store-buffer.

// TODO: Improve pipelining for LOADs.

// ****************************************************************

export Store_Buffer_IFC (..), mkStore_Buffer;

// ****************************************************************
// Imports from libraries

import FIFOF        :: *;
import SpecialFIFOs :: *;
import Vector       :: *;

// ----------------
// Imports from 'vendor' libs

import Cur_Cycle  :: *;
import GetPut_Aux :: *;
import Semi_FIFOF :: *;

// ----------------
// Local imports

import Utils       :: *;
import Instr_Bits  :: *;    // for funct5_LOAD/STORE ..
import Mem_Req_Rsp :: *;
import Inter_Stage :: *;    // for Retire_to_DMem_Commit

// ****************************************************************
// Debugging support

Integer verbosity = 0;

// ****************************************************************
// Generic Help functions

// Shift-amount to 8-lane-align according to LSBs of addr
function Bit #(6) fn_shamt (Bit #(64) addr);
   return { addr [2:0], 3'h0 };
endfunction

// Right-justified bit mask for given request size
function Bit #(64) fn_mask (Mem_Req_Size size);
   return case (size)
	     MEM_1B: 64'h_0000_0000_0000_00FF;
	     MEM_2B: 64'h_0000_0000_0000_FFFF;
	     MEM_4B: 64'h_0000_0000_FFFF_FFFF;
	     MEM_8B: 64'h_FFFF_FFFF_FFFF_FFFF;
	  endcase;
endfunction

// Return lane-aligned data and mask for req.
function Tuple2 #(Bit #(64), Bit #(64)) fn_lane_align (Mem_Req req);
   let addr  = req.addr;
   let data  = req.data;
   let mask  = fn_mask (req.size);
   let shamt = fn_shamt (addr);
   data = (data & mask) << shamt;
   mask = mask << shamt;
   return tuple2 (data, mask);
endfunction

// ****************************************************************

interface Store_Buffer_IFC #(numeric type store_buffer_size);

   method Action init (Initial_Params initial_params);

   // Note: FIFOs facing the CPU are module params

   // Facing memory
   interface FIFOF_O #(Mem_Req) fo_mem_req;
   interface FIFOF_I #(Mem_Rsp) fi_mem_rsp;
endinterface

// ****************************************************************

typedef enum { FSM_STATE_IDLE, FSM_STATE_RD_RSP } FSM_State
deriving (Bits, Eq, FShow);

module mkStore_Buffer #(FIFOF_O #(Mem_Req)               fo_req_from_CPU,
			FIFOF_I #(Mem_Rsp)               fi_rsp_to_CPU,
			FIFOF_O #(Retire_to_DMem_Commit) fo_commit_from_CPU)

                      (Store_Buffer_IFC #(store_buffer_size))

       provisos (Log #(store_buffer_size, log_store_buffer_size),
		 Add #(log_store_buffer_size, 1, ix_w));

   Integer i_store_buffer_size = valueOf (store_buffer_size);

   Reg #(File)  rg_logfile <- mkReg (InvalidFile);

   // ----------------
   // In-memory address limits and check

   Reg #(Bit #(64)) rg_addr_base_mem <- mkRegU;
   Reg #(Bit #(64)) rg_size_B_mem    <- mkRegU;

   function Bool fn_in_mem (Bit #(64) addr, Mem_Req_Size  size);
      Bit #(64) size_B = case (size)
			    MEM_1B: 1;
			    MEM_2B: 2;
			    MEM_4B: 4;
			    MEM_8B: 8;
			 endcase;
      return ((rg_addr_base_mem <= addr)
	      && ((addr + size_B) <= (rg_addr_base_mem + rg_size_B_mem)));
   endfunction

   // ----------------
   // Interface queues to/from mem

   FIFOF #(Mem_Req) f_req_to_mem   <- mkBypassFIFOF;
   FIFOF #(Mem_Rsp) f_rsp_from_mem <- mkPipelineFIFOF;

   // ----------------
   // Store-buffer state
   Vector #(store_buffer_size, Reg #(Mem_Req)) vrg_sb     <- replicateM (mkRegU);
   Reg #(Bit #(ix_w))                          rg_free_ix <- mkReg (0);

   Reg #(FSM_State) rg_fsm_state <- mkReg (FSM_STATE_IDLE);

   Action a_show_store_buffer =
   action
      wr_log_cont (rg_logfile, $format ("    store_buffer:"));
      for (Integer j = 0; j < i_store_buffer_size; j = j+1)
	 if (fromInteger (j) < rg_free_ix)
	    wr_log_cont (rg_logfile,
			 $format ("      %0d: ", j, fshow_Mem_Req (vrg_sb [j])));
   endaction;

   // ================================================================
   // Help functions

   // Sweep the store-buffer from oldest to newest, collecting
   // all updates for the same 64-bit word as addr arg.
   function Tuple2 #(Bit #(64), Bit #(64)) fn_collect_updates (Bit #(64) addr);
      Bit #(64) data = 0;
      Bit #(64) mask = 0;
      for (Integer j = (i_store_buffer_size - 1); j >= 0; j = j - 1) begin
	 Bool valid = (fromInteger (j) < rg_free_ix);
	 Bool addr_match = (addr [63:3] == vrg_sb [j].addr [63:3]);
	 match { .dataj, .maskj } = fn_lane_align (vrg_sb [j]);
	 if (valid && addr_match) begin
	    mask = mask | maskj;
	    data = (data & (~ maskj)) | dataj;
	 end
      end
      return tuple2 (data, mask);
   endfunction

   // ================================================================
   // Current CPU request and Mem response

   // Heads of incoming queues
   let cur_CPU_req = fo_req_from_CPU.first;
   let cur_mem_rsp = f_rsp_from_mem.first;

   Bool aligned = case (cur_CPU_req.size)
		     MEM_1B: True;
		     MEM_2B: (cur_CPU_req.addr [0]   == 1'h0);
		     MEM_4B: (cur_CPU_req.addr [1:0] == 2'h0);
		     MEM_8B: (cur_CPU_req.addr [2:0] == 3'h0);
		  endcase;

   Bool in_mem  = fn_in_mem (cur_CPU_req.addr, cur_CPU_req.size);

   Bool defer = ((! in_mem)
		 || (! aligned)
		 || (cur_CPU_req.req_type == funct5_FENCE)
		 || (cur_CPU_req.req_type == funct5_FENCE_I));

   Mem_Rsp default_rsp_to_CPU = Mem_Rsp {rsp_type: MEM_RSP_OK,
					 data:     ?,
					 req_type: cur_CPU_req.req_type,
					 size:     cur_CPU_req.size,
					 addr:     cur_CPU_req.addr,
					 inum:     cur_CPU_req.inum,
					 pc:       cur_CPU_req.pc,
					 instr:    cur_CPU_req.instr};

   // Net update and mask in store-buffer for given addr
   match { .upd_data, .upd_mask } = fn_collect_updates (cur_CPU_req.addr);

   // LSB-aligned mask for data
   let lsb_mask = fn_mask (cur_CPU_req.size);
   // Lane-aligned mask for data
   let  l_a_mask           = lsb_mask << fn_shamt (cur_CPU_req.addr);
   // Test if current read-request can be fully satisfied from store-buf
   //    (if so, no need to go to memory)
   Bool fully_in_store_buf = (upd_mask & l_a_mask) == l_a_mask;

   // ----------------------------------------------------------------
   // Requests deferred (not handled here): not in_mem, misaligned, FENCE, FENCE.I

   rule rl_defer ((rg_fsm_state == FSM_STATE_IDLE) && defer);
      let rsp = default_rsp_to_CPU;
      rsp.rsp_type = MEM_REQ_DEFERRED;
      rsp.data     = cur_CPU_req.data;

      fo_req_from_CPU.deq;
      fi_rsp_to_CPU.enq (rsp);

      if (verbosity != 0) begin
	 Fmt fmt = $format ("Spec_Store_Buf.rl_defer:");
	 if (cur_CPU_req.req_type == funct5_FENCE) fmt = fmt + $format (" FENCE");
	 else if (cur_CPU_req.req_type == funct5_FENCE_I) fmt = fmt + $format (" FENCE.I");
	 if (! aligned) fmt = fmt + $format (" misaligned");
	 if (! in_mem)  fmt = fmt + $format (" not in mem");
	 fmt = fmt + $format ("\n");
	 wr_log (rg_logfile, fmt);
	 wr_log_cont (rg_logfile,
		      $format ("    cur_CPU_req: ", fshow_Mem_Req (cur_CPU_req)));
	 wr_log_cont (rg_logfile,
		      $format ("    rsp_to_CPU:  ", fshow_Mem_Rsp (rsp, True)));
      end
   endrule

   // ----------------------------------------------------------------
   // Write requests

   // ----------------
   // Write-request; space available in store buffer: append
   rule rl_wr_req ((rg_fsm_state == FSM_STATE_IDLE)
		   && (! defer)
		   && (cur_CPU_req.req_type == funct5_STORE)
		   && (rg_free_ix < fromInteger (i_store_buffer_size - 1))
		   && (! fo_commit_from_CPU.notEmpty));

      vrg_sb [rg_free_ix] <= cur_CPU_req;
      rg_free_ix          <=  rg_free_ix + 1;

      fo_req_from_CPU.deq;
      fi_rsp_to_CPU.enq (default_rsp_to_CPU);

      if (verbosity != 0) begin
	 wr_log (rg_logfile, $format ("Spec_Store_Buf.rl_wr_req"));
	 a_show_store_buffer;
	 wr_log_cont (rg_logfile,
		      $format ("    %0d: ", rg_free_ix, fshow_Mem_Req (cur_CPU_req),
			       " (new)"));
      end
   endrule

   // ----------------
   // Process commit/discard message from CPU
   rule rl_commit_discard ((rg_fsm_state == FSM_STATE_IDLE)
			   && fo_commit_from_CPU.notEmpty);

      if (rg_free_ix != 0) begin
	 Retire_to_DMem_Commit x <- pop (fo_commit_from_CPU);

	 if (verbosity != 0) begin
	    wr_log (rg_logfile, $format ("Spec_Store_Buf.rl_commit_discard"));
	    wr_log_cont (rg_logfile, $format ("    ", fshow_Mem_Req (vrg_sb [0])));
	    wr_log_cont (rg_logfile, $format ("    new free_ix: %0d", rg_free_ix - 1));
	 end

	 if (x.commit) begin
	    f_req_to_mem.enq (vrg_sb [0]);
	    if (verbosity != 0)
	       wr_log_cont (rg_logfile, $format ("    commit to mem"));
	 end

	 if (verbosity != 0) begin
	    wr_log_cont (rg_logfile, $format ("    discarding store_buffer [0]"));
	    a_show_store_buffer;
	 end

	 // Shift up the store buffer
	 for (Integer j = 0; j < (i_store_buffer_size - 1); j = j + 1)
	    vrg_sb [j] <= vrg_sb [j+1];
	 rg_free_ix    <= rg_free_ix - 1;
      end
      else begin
	 if (verbosity != 0)
	    wr_log (rg_logfile,
		    $format ("ERROR: %m: Received commit/discard for empty store buffer"));
	 $finish (1);
      end
   endrule

   // ----------------
   // Discard (drain) write-responses from memory
   rule rl_mem_wr_rsp (cur_mem_rsp.req_type == funct5_STORE);
      let rsp <- pop (f_rsp_from_mem);

      if (verbosity != 0)
	 wr_log (rg_logfile, $format ("Spec_Store_Buf.rl_mem_wr_rsp (discard): ",
				      fshow_Mem_Rsp (rsp, False)));
   endrule

   // ----------------------------------------------------------------
   // Read requests

   // When store buffer contains the full update, no need to go to memory
   rule rl_rd_req_no_mem ((rg_fsm_state == FSM_STATE_IDLE)
			  && (! defer)
			  && (cur_CPU_req.req_type == funct5_LOAD)
			  && fully_in_store_buf);
      fo_req_from_CPU.deq;

      let rsp   = default_rsp_to_CPU;
      let shamt = fn_shamt (cur_CPU_req.addr);
      rsp.data = (upd_data >> shamt) & lsb_mask;
      fi_rsp_to_CPU.enq (rsp);

      if (verbosity != 0) begin
	 wr_log (rg_logfile, $format ("Spec_Store_Buf.rl_rd_req_no_mem"));
	 a_show_store_buffer;
         wr_log_cont (rg_logfile, $format ("    upd_data: %016h", upd_data));
         wr_log_cont (rg_logfile, $format ("    upd_mask: %016h", upd_mask));
         wr_log_cont (rg_logfile, $format ("    lsb_mask: %016h", lsb_mask));
	 wr_log_cont (rg_logfile,
		      $format ("    req_from_CPU: ", fshow_Mem_Req (cur_CPU_req)));
	 wr_log_cont (rg_logfile,
		      $format ("    rsp_to_CPU:   ", fshow_Mem_Rsp (rsp, True)));
      end
   endrule

   // When store buffer does not contain the full update, first load from memory
   rule rl_rd_req_mem ((rg_fsm_state == FSM_STATE_IDLE)
		       && (! defer)
		       && (cur_CPU_req.req_type == funct5_LOAD)
		       && (! fully_in_store_buf)
		       && (! fo_commit_from_CPU.notEmpty));

      f_req_to_mem.enq (cur_CPU_req);
      rg_fsm_state <= FSM_STATE_RD_RSP;

      if (verbosity != 0) begin
	 wr_log (rg_logfile, $format ("Spec_Store_Buf.rl_rd_req_mem:"));
	 wr_log_cont (rg_logfile, $format ("        ", fshow_Mem_Req (cur_CPU_req)));
      end
   endrule

   // Update data from memory with updates from store buffer and respond to CPU
   rule rl_rd_rsp ((rg_fsm_state == FSM_STATE_RD_RSP)
		   && (cur_mem_rsp.req_type == funct5_LOAD));

      let shamt            = fn_shamt (cur_mem_rsp.addr);
      let shifted_upd_data = upd_data >> shamt;
      let shifted_upd_mask = upd_mask >> shamt;

      Bit #(64) data = cur_mem_rsp.data;

      data = (data & (~ shifted_upd_mask)) | (shifted_upd_data & shifted_upd_mask);
      data = data & lsb_mask;

      let rsp  = cur_mem_rsp;
      rsp.data = data;

      fo_req_from_CPU.deq;
      f_rsp_from_mem.deq;
      fi_rsp_to_CPU.enq (rsp);

      rg_fsm_state <= FSM_STATE_IDLE;

      if (verbosity != 0) begin
	 wr_log (rg_logfile, $format ("Spec_Store_Buf.rl_rd_rsp"));
	 wr_log_cont (rg_logfile,
		      $format ("    cur_CPU_req: ", fshow_Mem_Req (cur_CPU_req)));
	 wr_log_cont (rg_logfile,
		      $format ("    cur_mem_rsp: ", fshow_Mem_Rsp (cur_mem_rsp, True)));
	 wr_log_cont (rg_logfile,
		      $format ("    rsp_to_CPU:  ", fshow_Mem_Rsp (rsp, True)));
	 wr_log_cont (rg_logfile,
		      $format ("    upd_data %016h >>%0d = %016h",
			       upd_data, shamt, shifted_upd_data));
	 wr_log_cont (rg_logfile,
		      $format ("    upd_mask %016h >>%0d = %016h",
			       upd_mask, shamt, shifted_upd_mask));
      end
   endrule

   // ================================================================
   // INTERFACE

   method Action init (Initial_Params initial_params);
      rg_logfile       <= initial_params.flog;
      rg_addr_base_mem <= initial_params.addr_base_mem;
      rg_size_B_mem    <= initial_params.size_B_mem;
   endmethod

   // Facing memory
   interface fo_mem_req = to_FIFOF_O (f_req_to_mem);
   interface fi_mem_rsp = to_FIFOF_I (f_rsp_from_mem);
endmodule

// ****************************************************************

endpackage
