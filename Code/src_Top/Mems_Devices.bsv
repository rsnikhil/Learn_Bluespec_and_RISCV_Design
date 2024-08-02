// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Mems_Devices;

// ****************************************************************
// The "Memory System" for Drum/Fife

// TODO: interrupt requests from UART, other devices
// ****************************************************************
// Imports from libraries

import FIFOF        :: *;

// ----------------
// Imports from 'vendor' libs

import Cur_Cycle :: *;
import Semi_FIFOF :: *;

// ----------------
// Local imports

import Utils        :: *;
import Instr_Bits   :: *;    // for funct5_LOAD/STORE/...
import Mem_Req_Rsp  :: *;
import Inter_Stage  :: *;
import Store_Buffer :: *;

// ****************************************************************
// Debugging support

Integer verbosity = 0;

// ****************************************************************

interface Mems_Devices_IFC;
   method Action init (Initial_Params initial_params);
   method ActionValue #(Bit #(64)) rd_MTIME;
endinterface

// ****************************************************************

typedef enum {CLIENT_IMEM, CLIENT_DMEM, CLIENT_MMIO} Client_ID
deriving (Bits, Eq, FShow);

module mkMems_Devices #(FIFOF_O #(Mem_Req) fo_IMem_req,
			FIFOF_I #(Mem_Rsp) fi_IMem_rsp,

			FIFOF_O #(Mem_Req) fo_DMem_req,
			FIFOF_I #(Mem_Rsp) fi_DMem_rsp,
			FIFOF_O #(Retire_to_DMem_Commit) fo_DMem_commit,

			FIFOF_O #(Mem_Req) fo_MMIO_req,
			FIFOF_I #(Mem_Rsp) fi_MMIO_rsp)
                      (Mems_Devices_IFC);

   // Store buffer for speculative mem ops
   Store_Buffer_IFC #(4) spec_sto_buf <- mkStore_Buffer (fo_DMem_req,
							 fi_DMem_rsp,
							 fo_DMem_commit);

   Reg #(Bool)  rg_running <- mkReg (False);
   Reg #(File)  rg_logfile <- mkReg (InvalidFile);

   Reg #(Bit #(64)) rg_MTIME <- mkReg (0);

   // ****************************************************************
   // BEHAVIOR

   // ================================================================

   (* fire_when_enabled, no_implicit_conditions *)    // On every cycle
   rule rl_count_MTIME;
      rg_MTIME <= rg_MTIME + 1;
   endrule

   function Action fa_mem_req_rsp (FIFOF_O #(Mem_Req) fo_mem_req,
				   FIFOF_I #(Mem_Rsp) fi_mem_rsp,
				   Client_ID          client_id,
				   Integer            verbosity);
      action
	 let mem_req <- pop_o (fo_mem_req);
	 Bit #(128) wdata = zeroExtend (mem_req.data);
	 Bit #(96) result <- c_mems_devices_req_rsp (mem_req.inum,
						     zeroExtend (pack (mem_req.req_type)),
						     zeroExtend (pack (mem_req.size)),
						     mem_req.addr,
						     zeroExtend (pack (client_id)),
						     wdata);
	 Mem_Rsp mem_rsp = Mem_Rsp {inum:     mem_req.inum,
				    pc:       mem_req.pc,
				    instr:    mem_req.instr,
				    req_type: mem_req.req_type,
				    size:     mem_req.size,
				    addr:     mem_req.addr,
				    rsp_type: unpack (truncate (result [31:0])),
				    data:     result [95:32]};

	 fi_mem_rsp.enq (mem_rsp);

	 if (verbosity != 0) begin
	    wr_log (rg_logfile, $format ("mkMems_Devices: for client ", fshow (client_id)));
	    wr_log_cont (rg_logfile, $format ("    ", fshow_Mem_Req (mem_req)));
	    Bool show_data = (mem_req.req_type != funct5_STORE);
	    wr_log_cont (rg_logfile, $format ("    ", fshow_Mem_Rsp (mem_rsp, show_data)));
	 end
      endaction
   endfunction

   // Fetch mem ops
   rule rl_IMem_req_rsp (rg_running);
      fa_mem_req_rsp (fo_IMem_req, fi_IMem_rsp, CLIENT_IMEM, 0);
   endrule

   // Speculative mem ops
   rule rl_DMem_req_rsp (rg_running);
      Bit #(32) client = 1;
      fa_mem_req_rsp (spec_sto_buf.fo_mem_req, spec_sto_buf.fi_mem_rsp, CLIENT_DMEM, 1);
   endrule

   // Non-speculative mem ops
   rule rl_MMIO_req_rsp (rg_running);
      Bit #(32) client = 2;
      fa_mem_req_rsp (fo_MMIO_req, fi_MMIO_rsp, CLIENT_MMIO, 1);
   endrule

   // ================================================================
   // INTERFACE

   method Action init (Initial_Params initial_params) if (! rg_running);
      rg_logfile <= initial_params.flog;
      spec_sto_buf.init (initial_params);
      c_mems_devices_init (0);
      rg_running <= True;
   endmethod

   method ActionValue #(Bit #(64)) rd_MTIME;
      return rg_MTIME;
   endmethod
endmodule

// ****************************************************************
// Imported C functions for a memories-and-devices model
// All devices are accessed just like memory (MMIO).

import "BDPI"
function Action c_mems_devices_init (Bit #(32) dummy);

// result and wdata are passed as pointers.
// result is passed as first arg to C function.
// result is 32-bits of status (MEM_OK, MEM_ERR) followed by rdata.
// client is 0 for IMem, 1 for DMem, 2 for MMIO

import "BDPI"
function ActionValue #(Bit #(96)) c_mems_devices_req_rsp (Bit #(64) inum,
							  Bit #(32) req_type,
							  Bit #(32) req_size,
							  Bit #(64) addr,
							  Bit #(32) client,
							  Bit #(128) wdata);

// ****************************************************************

endpackage
