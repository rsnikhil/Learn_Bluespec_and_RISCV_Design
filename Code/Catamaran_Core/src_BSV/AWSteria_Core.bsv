// Copyright (c) 2021-2023 Bluespec, Inc. All Rights Reserved.
// Author: Rishiyur S. Nikhil

package AWSteria_Core;

// ================================================================
// This package defines mkCatamaran_Core, which is a top-level
// "substitutable core" in Catamaran; it is instantiated by the fixed
// Catamaran_System.

// This module has three subsystems:
//
//     mkCatamaran_Core
//         mkHost_Control_Status
//         mkDebug_Module
//         mkCatamaran_Core_Inner

// Most of the core components are in mkCatamaran_Core_Inner (CPU with
// caches and MMUs, Boot ROM, PLIC, Near-Mem-IO/CLINT).

// mkCatamaran_Core_Inner is a separate clock and reset domain.
// It typically runs at a slower clock than the default clock.

// Either Host_Control_Status or Debug_Module can reset Catamaran_Core_Inner.

// ================================================================
// Lib imports

// BSV libs
import Clocks       :: *;

import Vector       :: *;
import FIFOF        :: *;
import GetPut       :: *;
import ClientServer :: *;
import Connectable  :: *;

// ----------------
// BSV additional libs

import Cur_Cycle  :: *;
import GetPut_Aux :: *;
import Semi_FIFOF :: *;

// ----------------
// AXI

import AXI4_Types     :: *;

// ================================================================
// Project imports

import AWSteria_Core_IFC             :: *;

// Host Control and Status
import Host_Control_Status           :: *;

// Debug Module
// import DM_Common      :: *;    // For Server_DMI
// import Debug_Module   :: *;
// import DM_CPU_Req_Rsp :: *;

// Inner core
import Catamaran_Core_Inner_Reclocked :: *;
import Catamaran_Core_Inner           :: *;

// ================================================================
// Interface specialization to non-polymorphic type.
// These parameter values are used in Catamaran CVA6.

typedef AWSteria_Core_IFC #(// AXI widths for Mem
			    AXI4_Wd_Id, AXI4_Wd_Addr, AXI4_Wd_Data_A, AXI4_Wd_User,

			    // AXI widths for MMIO
			    AXI4_Wd_Id, AXI4_Wd_Addr, AXI4_Wd_Data_B, AXI4_Wd_User,

			    // AXI widths for DMA port
			    AXI4_Wd_Id, AXI4_Wd_Addr, AXI4_Wd_Data_A, AXI4_Wd_User,

			    // UART, virtio 1,2,3,4
			    N_Core_External_Interrupt_Sources
			    ) AWSteria_Core_IFC_Specialized;

// ================================================================
// mkAWSteria_Core is thin wrapper around mkCatamaran_Core_Inner,
// optionally selecting a slower clock for it.  If we use a slower
// clock, mkCatamaran_Core_Inner_Reclocked contains all the
// clock-crossings.

(* synthesize *)
module mkAWSteria_Core #(Clock clk1,        // extra clock
			 Clock clk2,        // extra clock
			 Clock clk3,        // extra clock
			 Clock clk4,        // extra clock
			 Clock clk5)        // extra clock
                       (AWSteria_Core_IFC_Specialized);

   Integer verbosity = 0;

   let clk_cur  <- exposeCurrentClock;
   let rstn_cur <- exposeCurrentReset;

   // ================================================================
   // Host Control-Status
   Host_Control_Status_IFC host_cs <- mkHost_Control_Status;

   // ================================================================
   // Defines 'core_inner' interface to mkCore_Inner without reclocking

   /*
   // Instantiate inner core with with controllable reset on current clock

   messageM ("\nINFO: mkAWSteria_System --> AWSteria_Core: no clock crossing.");

   MakeResetIfc innerRstIfc <- mkReset (2,           // # of delay stages
					True,        // start in reset
					clk_cur);    // for which this is a reset

   let innerReset = innerRstIfc.new_rst;

   // Inner core on current clock, resettable
   Catamaran_Core_Inner_IFC
   core_inner <- mkCatamaran_Core_Inner (reset_by  innerReset);
   */

   // ----------------
   // Instantiate inner core with with controllable reset and slower clock

   messageM ("\nINFO: mkAWSteria_System --> AWSteria_Core: with clock crossings.");

   // Choose clock, depending on target platform.
   // One of these must be defined.
   let innerCLK = clk_cur;
   messageM ("\nINFO: Core clock is clk_cur");

   MakeResetIfc innerRstIfc <- mkReset (2,            // # of delay stages
					True,         // start in reset
					innerCLK);    // for which this is a reset

   let innerReset = innerRstIfc.new_rst;

   // Inner core on inner clock, resettable
   Catamaran_Core_Inner_IFC
   core_inner_reclocked <- mkCatamaran_Core_Inner (clocked_by innerCLK,
						   reset_by   innerReset);

   // Clock crossings into inner core
   Catamaran_Core_Inner_IFC
   core_inner <- mkCatamaran_Core_Inner_Reclocked (clk_cur,  rstn_cur,
						   innerCLK, innerReset,
						   core_inner_reclocked);

   // ================================================================
   // Assert inner reset if commanded by host_cs or by Debug Module's NDM reset
   // TODO: debug_module_ndm_reset should also be a level, not a token

   Reg #(Bool) rg_core_reset_message_displayed <- mkReg (False);

   rule rl_assert_reset_for_inner_core (host_cs.mv_assert_core_reset);
      if (host_cs.mv_assert_core_reset) begin
	 if (! rg_core_reset_message_displayed) begin
	    if (verbosity != 0)
	       $display ("AWSteria_Core: asserting Core_Inner reset due to host-control");
	    rg_core_reset_message_displayed <= True;
	 end
      end
      else begin
	 if (verbosity != 0)
	    $display ("AWSteria_Core: asserting Core_Inner reset due to NDM reset from Debug Module");
      end
      innerRstIfc.assertReset();
   endrule

   rule rl_on_deassert_core_reset (rg_core_reset_message_displayed
				   && (! host_cs.mv_assert_core_reset));
      if (verbosity != 0)
	 $display ("AWSteria_Core: de-asserting Core_Inner reset due to host-control");
      // Prepare for next core reset
      rg_core_reset_message_displayed <= False;
   endrule

   // ================================================================
   // Connect host controls to inner core

   // PC trace
   FIFOF_I #(Tuple2 #(Bool, Bit #(64))) fi_pc_trace_control = dummy_FIFOF_I;
   mkConnection (host_cs.fo_pc_trace_control, fi_pc_trace_control);

   // Simulation verbosity
   FIFOF_I #(Tuple2 #(Bit #(4), Bit #(64))) fi_verbosity_control = dummy_FIFOF_I;
   mkConnection (host_cs.fo_verbosity_control, fi_verbosity_control);

   // Host control of 'watch tohost'
   FIFOF_I #(Tuple2 #(Bool, Bit #(64))) fi_watch_tohost_control = dummy_FIFOF_I;
   mkConnection (host_cs.fo_watch_tohost_control, fi_watch_tohost_control);

   // ================================================================
   // INTERFACE

   // ----------------------------------------------------------------
   // Interfaces that go directly out to AWSteria_Core_IFC

   // ----------------
   // AXI4 interfaces for memory, MMIO, and DMA
   // Note: DMA may or may not be coherent, depending on internal Core architecture.

   interface AXI4_Master_IFC mmio_M = core_inner.mmio_M;

   interface AXI4_Master_IFC mem_M  = dummy_AXI4_Master_ifc;
   interface AXI4_Slave_IFC  dma_S  = dummy_AXI4_Slave_ifc;

   // ----------------
   // External interrupt sources

   method Action ext_interrupts (Bit #(t_n_interrupt_sources) x);
   endmethod

   // ----------------
   // Non-maskable interrupt request

   interface fi_nmi = dummy_FIFOF_I;

   // ----------------
   // Misc I/O streams

   interface fo_misc = dummy_FIFOF_O;
   interface fi_misc = dummy_FIFOF_I;

   // ----------------
   // Tandem Verification output

   interface fo_tv_info = dummy_FIFOF_O;

   // ----------------------------------------------------------------
   // Debug Module interfaces

   // DMI (Debug Module Interface) facing remote debugger

   interface Server_Semi_FIFOF se_dmi = dummy_Server_Semi_FIFOF;

   // Non-Debug-Module Reset (reset "all" except DM)
   // These Bit#(0) values are just tokens for signaling 'reset request' and 'reset done'

   // TODO; we stub this out for now. In future, we could use this to
   // reset modules in Catamaran__System.

   interface Client_Semi_FIFOF cl_ndm_reset = dummy_Client_Semi_FIFOF;

   // ----------------------------------------------------------------
   // Host control and status

   interface Server_Semi_FIFOF se_control_status = host_cs.se_control_status;
endmodule

// ================================================================

endpackage
