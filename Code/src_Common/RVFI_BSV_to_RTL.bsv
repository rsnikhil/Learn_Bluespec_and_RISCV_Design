// Copyright (c) 2026 Rishiyur S. Nikhil.  All Rights Reserved

package RVFI_BSV_to_RTL;

// ****************************************************************
// Transactor to convert a FIFO_O method output carrying an
// RVFI_DII_Execution struct into separate buses for each of the
// fields, suitable for reading in Verilog.

// ****************************************************************
// Imports from libraries

import FIFOF :: *;

// ----------------
// Imports from 'vendor' libs

import Semi_FIFOF :: *;
import EdgeFIFOFs :: *;

// ----------------
// Local imports

import RVFI_DII_Types :: *;

// ****************************************************************

interface RVFI_RTL_M_IFC #(numeric type xlen, numeric type memwidth);
   (* always_ready, result="rvfi_valid" *)     method Bool                    rvfi_valid;

   (* always_ready, result="rvfi_order" *)     method Bit#(64)                rvfi_order;
   (* always_ready, result="rvfi_trap"  *)     method Bool                    rvfi_trap;
   (* always_ready, result="rvfi_halt"  *)     method Bool                    rvfi_halt;
   (* always_ready, result="rvfi_intr"  *)     method Bool                    rvfi_intr;

   (* always_ready, result="rvfi_insn"  *)     method Bit#(32)                rvfi_insn;

   (* always_ready, result="rvfi_rs1_addr" *)  method Bit#(5)                 rvfi_rs1_addr;
   (* always_ready, result="rvfi_rs2_addr" *)  method Bit#(5)                 rvfi_rs2_addr;
   (* always_ready, result="rvfi_rs1_data" *)  method Bit#(xlen)              rvfi_rs1_data;
   (* always_ready, result="rvfi_rs2_data" *)  method Bit#(xlen)              rvfi_rs2_data;

   (* always_ready, result="rvfi_pc_rdata" *)  method Bit#(xlen)              rvfi_pc_rdata;
   (* always_ready, result="rvfi_pc_wdata" *)  method Bit#(xlen)              rvfi_pc_wdata;

   (* always_ready, result="rvfi_mem_wdata" *) method Bit#(memwidth)          rvfi_mem_wdata;
   (* always_ready, result="rvfi_rd_addr" *)   method Bit#(5)                 rvfi_rd_addr;
   (* always_ready, result="rvfi_rd_wdata" *)  method Bit#(xlen)              rvfi_rd_wdata;
   (* always_ready, result="rvfi_mem_addr" *)  method Bit#(xlen)              rvfi_mem_addr;
   (* always_ready, result="rvfi_mem_rmask" *) method Bit#(TDiv#(memwidth,8)) rvfi_mem_rmask;
   (* always_ready, result="rvfi_mem_wmask" *) method Bit#(TDiv#(memwidth,8)) rvfi_mem_wmask;
   (* always_ready, result="rvfi_mem_rdata" *) method Bit#(xlen)              rvfi_mem_rdata;
endinterface

// ****************************************************************

interface RVFI_BSV_to_RTL_IFC #(numeric type xlen,
				numeric type memwidth);
   interface FIFOF_I #(RVFI_DII_Execution #(xlen, memwidth)) fi_rvfi_reports;
   interface RVFI_RTL_M_IFC #(xlen, memwidth)                rvfi_RTL_ports;
endinterface

// ****************************************************************
// M transactor

module mkRVFI_BSV_to_RTL (RVFI_BSV_to_RTL_IFC #(xlen, memwidth));

   Bool unguarded = True;
   Bool guarded   = False;

   // This FIFO is guarded on BSV side, unguarded on RTL side
   FIFOF #(RVFI_DII_Execution #(xlen, memwidth)) fifo <- mkGFIFOF (guarded, unguarded);

   (* no_implicit_conditions, fire_when_enabled *)
   rule rl_consume (fifo.notEmpty);
      fifo.deq;
   endrule

   // ----------------------------------------------------------------
   interface FIFOF_I fi_rvfi_reports = to_FIFOF_I (fifo);

   interface RVFI_RTL_M_IFC rvfi_RTL_ports;
	 method rvfi_valid     = fifo.notEmpty;
	 method rvfi_order     = fifo.first.rvfi_order;
	 method rvfi_trap      = fifo.first.rvfi_trap;
	 method rvfi_halt      = fifo.first.rvfi_halt;
	 method rvfi_intr      = fifo.first.rvfi_intr;

	 method rvfi_insn      = fifo.first.rvfi_insn;

	 method rvfi_rs1_addr  = fifo.first.rvfi_rs1_addr;
	 method rvfi_rs2_addr  = fifo.first.rvfi_rs2_addr;
	 method rvfi_rs1_data  = fifo.first.rvfi_rs1_data;
	 method rvfi_rs2_data  = fifo.first.rvfi_rs2_data;

	 method rvfi_pc_rdata  = fifo.first.rvfi_pc_rdata;
	 method rvfi_pc_wdata  = fifo.first.rvfi_pc_wdata;

	 method rvfi_mem_wdata = fifo.first.rvfi_mem_wdata;
	 method rvfi_rd_addr   = fifo.first.rvfi_rd_addr;
	 method rvfi_rd_wdata  = fifo.first.rvfi_rd_wdata;
	 method rvfi_mem_addr  = fifo.first.rvfi_mem_addr;
	 method rvfi_mem_rmask = fifo.first.rvfi_mem_rmask;
	 method rvfi_mem_wmask = fifo.first.rvfi_mem_wmask;
	 method rvfi_mem_rdata = fifo.first.rvfi_mem_rdata;
   endinterface

endmodule

// ****************************************************************

endpackage
