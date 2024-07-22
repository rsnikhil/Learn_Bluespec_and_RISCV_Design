// Copyright (c) 2024 Bluespec, Inc. All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Catamaran_Core_Inner_Reclocked;

// ================================================================
// This package defines a 'reclocking' module, i.e., a function
//
//    Clock -> Clock -> Catamaran_Core_Inner_IFC -> Module (Catamaran_Core_Inner_IFC)
//
// where the input and output Catamaran_Core_Inner_IFC interfaces
// run on different clocks

// ================================================================
// Lib imports

// from BSV library
// import Vector       :: *;
import GetPut       :: *;
import ClientServer :: *;
import Connectable  :: *;
import Clocks       :: *;

// ----------------
// BSV additional libs

import Semi_FIFOF :: *;

// AXI
import AXI4_Types         :: *;
import AXI4_ClockCrossing :: *;

// ================================================================
// Project imports

import AWSteria_Core_IFC   :: *;
import Catamaran_Core_Inner :: *;

// ================================================================

function FIFOF_O #(t) fn_SyncFIFOIfc_to_FIFOF_O (SyncFIFOIfc #(t) syncfifo);
   return interface FIFOF_O;
	     method first    = syncfifo.first;
	     method deq      = syncfifo.deq;
	     method notEmpty = syncfifo.notEmpty;
	  endinterface;
endfunction

function FIFOF_I #(t) fn_SyncFIFOIfc_to_FIFOF_I (SyncFIFOIfc #(t) syncfifo);
   return interface FIFOF_I;
	     method enq     = syncfifo.enq;
	     method notFull = syncfifo.notFull;
	  endinterface;
endfunction

// ================================================================

module mkCatamaran_Core_Inner_Reclocked
   #(Clock clk_fast, Reset rst_fast,
     Clock clk_slow, Reset rst_slow,
     Catamaran_Core_Inner_IFC  core_inner) (Catamaran_Core_Inner_IFC);

   Integer depth = 4;    // For SyncFIFOs

   // ----------------------------------------------------------------
   // Interfaces that go directly out to AWSteria_Core_IFC

   // ----------------
   // AXI4 interfaces for memory

   let mmio_AXI4_clock_crossing <- mkAXI4_ClockCrossing (clk_slow, rst_slow,
							 clk_fast, rst_fast);
   mkConnection (core_inner.mmio_M, mmio_AXI4_clock_crossing.from_M);

   // ================================================================
   // INTERFACE

   // ----------------------------------------------------------------
   // Interfaces that go directly out to AWSteria_Core_IFC

   // ----------------
   // AXI4 interfaces for memory

   interface AXI4_Master_IFC mmio_M = mmio_AXI4_clock_crossing.to_S;

endmodule

// ================================================================

endpackage
