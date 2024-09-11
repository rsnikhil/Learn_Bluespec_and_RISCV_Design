// Copyright (c) 2024 Rishiyur S. Nikhil and Bluespec, Inc. All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Dbg_Stub;

// ****************************************************************
// mkDbg_Stub enables debugging the CPU from a remote debugger ("Dbg").
// Dbg can be GDB, LLDB, OpenOCD, or EDB, with or without intermediaries
//     such as OpenOCD, RISC-V Debug Module, JTAG.
// It receives request packets from Dbg and sends them into the CPU.
// It receives responses from the CPU and sends responsed packets to Dbg.

// Typical connection setups:
//  EDB <-----------------------------------------------------------> mkDbg_Stub
//          OpenOCD[DMI/JTAG] <-> JTAG endpoint <-> Debug Moodule <-> mkDbg_Stub
//  GDB <-> gdbstub[dhrr] <-----------------------------------------> mkDbg_Stub
//  GDB <-> gdbstub[DMI] <------------------------> Debug Moodule <-> mkDbg_Stub
//  GDB <-> OpenOCD[DMI/JTAG] <-> JTAG endpoint <-> Debug Moodule <-> mkDbg_Stub
// (for GDB also read LLDB)

// The name 'Dbg_Stub' follows the example of well known 'gdbstub'; it
// plays an analogous role as intermediary between debugger and
// debuggee.

// This version of mkDbg_Stub is for simulation (Bluesim or Verilog sim).
// It imports C code to receive a TCP connection from Dbg, and merely
// forwards packets in both directions.

// A hardware implementation of this module will connect the packet
// transport mechanism to the CPU.

// ****************************************************************
// Imports from libraries

import FIFOF        :: *;
import Vector       :: *;

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

// ****************************************************************
// Debugging support for this module

Integer verbosity = 0;

// ****************************************************************
// INTERFACE DECL

interface Dbg_Stub_IFC;
   method Action init (Initial_Params initial_params);
endinterface

// ****************************************************************
// MODULE (implementaton)
// See Inter_Stage.bsv for declarations of Dbg_to/from_CPU_Pkt

module mkDbg_Stub #(FIFOF_I #(Dbg_to_CPU_Pkt)   fi_dbg_to_CPU_pkt,
		    FIFOF_O #(Dbg_from_CPU_Pkt) fo_dbg_from_CPU_pkt)
                  (Dbg_Stub_IFC);

   Reg #(Bool)  rg_running <- mkReg (False);

   // ****************************************************************
   // BEHAVIOR

   // Relay from debugger to CPU
   rule rl_dbg_to_CPU (rg_running);
      Vector #(3, Bit #(64)) v3 <- bdpi_edbstub_recv_dbg_to_CPU_pkt;
      Bit #(64) v0 = v3 [0];
      let pkt_to_CPU
      = Dbg_to_CPU_Pkt {pkt_type:  unpack (truncate (v0 [7:0])),
			rw_target: unpack (truncate (v0 [15:8])),
			rw_op:     unpack (truncate (v0 [23:16])),
			rw_size:   unpack (truncate (v0 [31:24])),
			rw_addr:   truncate (v3 [1]),
			rw_wdata:  truncate (v3 [2])};
      if (pkt_to_CPU.pkt_type != Dbg_to_CPU_NOOP) begin
	 fi_dbg_to_CPU_pkt.enq (pkt_to_CPU);
	 if (verbosity != 0) begin
	    $display ("----------------");
	    $display ("mkDbg_Stub: rec'd from debugger: ",
		      fshow_Dbg_to_CPU_Pkt (pkt_to_CPU));
	 end
      end
   endrule

   // Relay to debugger from CPU
   rule rl_dbg_from_CPU (rg_running);
      let pkt_in <- pop_o (fo_dbg_from_CPU_pkt);
      Bit #(32) pkt_type = zeroExtend (pack (pkt_in.pkt_type));
      Bit #(64) payload  = zeroExtend (pkt_in.payload);
      bdpi_edbstub_send_dbg_from_CPU_pkt (pkt_type, payload);

      if (verbosity != 0)
	 $display ("mkDbg_Stub: sent to debugger: ",
		   fshow_Dbg_from_CPU_Pkt (pkt_in));
   endrule

   // ================================================================
   // INTERFACE

   method Action init (Initial_Params initial_params) if (! rg_running);
      let listen_socket = initial_params.dbg_listen_socket;
      if (listen_socket != 0) begin
	 bdpi_edbstub_init (listen_socket);
	 rg_running <= True;
	 if (verbosity != 0)
	    $display ("With debugger");
      end
      else
	 if (verbosity != 0)
	    $display ("Without debugger");
   endmethod

endmodule

// ****************************************************************
// Imported C functions from edbstub.c

import "BDPI"
function Action bdpi_edbstub_init (Bit #(16) listen_port);

import "BDPI"
function ActionValue #(Vector #(3, Bit #(64)))
         bdpi_edbstub_recv_dbg_to_CPU_pkt ();

import "BDPI"
function Action
         bdpi_edbstub_send_dbg_from_CPU_pkt (Bit #(32) pkt_type, Bit #(64) x);

import "BDPI"
function Action bdpi_edbstub_shutdown (Bit #(32) dummy);

// ****************************************************************

endpackage
