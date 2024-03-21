// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Mems_Devices;

// ****************************************************************
// Imports from libraries

import FIFOF        :: *;

// ----------------
// Imports from 'vendor' libs

import Cur_Cycle :: *;
import Semi_FIFOF :: *;

// ----------------
// Local imports

import Utils       :: *;
import Instr_Bits  :: *;    // for funct5_STORE
import Mem_Req_Rsp :: *;
import Inter_Stage :: *;

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

// Discharges the head of the store-buffer.
// 'commit' is 1 to commit (perform the write), 0 to discard

import "BDPI"
function Action c_mems_store_complete (Bit #(64) inum, Bit #(32)  commit);

// TODO: interrupt requests

// ****************************************************************

Integer verbosity = 0;

// ****************************************************************

interface Mems_Devices_IFC;
   method Action init (Initial_Params initial_params);
endinterface

// ****************************************************************

module mkMems_Devices #(FIFOF_O #(Mem_Req) fo_IMem_req,
			FIFOF_I #(Mem_Rsp) fi_IMem_rsp,

			FIFOF_O #(Mem_Req) fo_DMem_req,
			FIFOF_I #(Mem_Rsp) fi_DMem_rsp,
			FIFOF_O #(Retire_to_DMem_Commit) fo_DMem_commit,

			FIFOF_O #(Mem_Req)               fo_MMIO_req,
			FIFOF_I #(Mem_Rsp)               fi_MMIO_rsp)
                      (Mems_Devices_IFC);

   Reg #(Bool)  rg_running <- mkReg (False);
   Reg #(File)  rg_logfile <- mkReg (InvalidFile);

   // ================================================================
   // BEHAVIOR

   function Action fa_mem_req_rsp (FIFOF_O #(Mem_Req) fo_mem_req,
				   FIFOF_I #(Mem_Rsp) fi_mem_rsp,
				   Bit #(32)          client);
      action
	 let mem_req <- pop_o (fo_mem_req);
	 Bit #(128) wdata = zeroExtend (mem_req.data);
	 Bit #(96) result <- c_mems_devices_req_rsp (mem_req.inum,
						     zeroExtend (pack (mem_req.req_type)),
						     zeroExtend (pack (mem_req.size)),
						     mem_req.addr,
						     client,
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
	    wr_log (rg_logfile, $format ("mkMems_Devices"));
	    wr_log (rg_logfile, $format ("    ", fshow_Mem_Req (mem_req)));
	    Bool show_data = (mem_req.req_type != funct5_STORE);
	    wr_log (rg_logfile, $format ("    ", fshow_Mem_Rsp (mem_rsp, show_data)));
	 end
      endaction
   endfunction

   rule rl_IMem_req_rsp (rg_running);
      fa_mem_req_rsp (fo_IMem_req, fi_IMem_rsp, 0);
   endrule

   rule rl_DMem_req_rsp (rg_running);
      fa_mem_req_rsp (fo_DMem_req, fi_DMem_rsp, 1);
   endrule

   rule rl_MMIO_req_rsp (rg_running);
      fa_mem_req_rsp (fo_MMIO_req, fi_MMIO_rsp, 2);
   endrule

   rule rl_DMem_commit (rg_running);
      let x <- pop_o (fo_DMem_commit);
      c_mems_store_complete (x.inum, zeroExtend (pack (x.commit)));
   endrule

   // ================================================================
   // INTERFACE
   method Action init (Initial_Params initial_params) if (! rg_running);
      rg_logfile <= initial_params.flog;
      c_mems_devices_init (0);
      rg_running <= True;
   endmethod
endmodule

// ****************************************************************

endpackage
