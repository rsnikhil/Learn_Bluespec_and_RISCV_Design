// Copyright (c) 2022-2024 Bluespec, Inc. All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Catamaran_Core_Inner;

// ================================================================
// This package defines module 'mkCatamaran_Core_Inner' that is
// located as follows:
//
//     mkCatamaran_Core
//         mkHost_Control_Status
//         mkCatamaran_Core_Inner
//
// The inner core can be run at a slower clock.
// The inner core can be reset by mkHost_Control_Status.

// The inner core contains:
//     - mkCPU                  The Drum/Fife CPU
//     - mkCore_MMIO_Fabric     To connect CPU to Catamaran MMIO/Memory and to Clint
//     - mkNear_Mem_IO_AXI4     (a.k.a. CLINT; memory-mapped MTIME, MTIMECMP, MSIP, ...)
// and their connecting logic.

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

import AXI4_Types       :: *;
import AXI4_Fabric      :: *;

// ================================================================
// Project imports

import SoC_Map     :: *;

// ----------------
// Defs used in Catamaran_Core_Inner_IFC and related defs

import AWSteria_Core_IFC :: *;    // For AXI4_Wd_{Id,Addr,Data_A,Data_B,_User}
                                  // and N_Core_External_Interrupt_Sources

// import ISA_Decls         :: *;
import Fabric_Defs       :: *;    // for Wd_{Id,Addr,Data,User}

import TV_Info           :: *;    // Tandem Verification info

// ----------------
// RISC-V CPU and related IPs

import Utils        :: *;
import Mem_Req_Rsp  :: *;
import CPU_IFC      :: *;    // Fife/Drum CPU interface
import CPU          :: *;    // Fife/Drum CPU
import Store_Buffer :: *;    // Used for Fife; unused for Drum

import Adapter_ReqRsp_AXI4 :: *;    // Adapter CPU Mem_Req/Mem_Rsp to AXI4

import Core_MMIO_Fabric :: *;    // CPU MMIO to Fabric, Near_Mem_IO

import Near_Mem_IO_AXI4  :: *;

// ================================================================
// Core_Inner's interface:
//     mostly AWSteria_Core_IFC, minus 'se_control_status' since mkHost_Control_Status
//         is outside and controls a reset for Core_Inner
//     plus other control interfaces from mkHost_Control_Status to Core_Inner

interface Catamaran_Core_Inner_IFC;
   // ----------------------------------------------------------------
   // Interfaces that go directly out to AWSteria_Core_IFC

   // ----------------
   // AXI4 interfaces for memory

   interface AXI4_Master_IFC #(AXI4_Wd_Id, AXI4_Wd_Addr, AXI4_Wd_Data_B, AXI4_Wd_User) mmio_M;

endinterface

// ================================================================
// Catamaran_Core_Inner: single clocked

typedef enum {
   MODULE_STATE_INIT_0,       // start post-reset initializations
   MODULE_STATE_INIT_1,       // finish post-reset initializations

   MODULE_STATE_READY
   } Module_State
deriving (Bits, Eq, FShow);

(* synthesize *)
module mkCatamaran_Core_Inner (Catamaran_Core_Inner_IFC);

   Integer verbosity = 0;    // Normally 0; non-zero for debugging

   Reg #(Module_State) rg_module_state <- mkReg (MODULE_STATE_INIT_0);

   // System address map
   SoC_Map_IFC  soc_map  <- mkSoC_Map;

   // The CPU
   CPU_IFC cpu <- mkCPU;

   // Store buffer for speculative mem ops
   Store_Buffer_IFC #(4) spec_sto_buf <- mkStore_Buffer (cpu.fo_DMem_S_req,
							 cpu.fi_DMem_S_rsp,
							 cpu.fo_DMem_S_commit);

   // Adapter from CPU IMem to AXI4
   AXI4_Master_IFC #(Wd_Id, Wd_Addr, Wd_Data, Wd_User)
      imem_AXI4_M <- mkAdapter_ReqRsp_AXI4 ("IMem AXI4 Adapter",
					    0,    // verbosity
					    cpu.fo_IMem_req,
					    cpu.fi_IMem_rsp);

   // Adapter from CPU speculative DMem to AXI4
   AXI4_Master_IFC #(Wd_Id, Wd_Addr, Wd_Data, Wd_User)
      dmem_S_AXI4_M <- mkAdapter_ReqRsp_AXI4 ("DMem_S AXI4 Adapter",
					      0,    // verbosity
					      spec_sto_buf.fo_mem_req,
					      spec_sto_buf.fi_mem_rsp);

   // Adapter from CPU non-speculative DMem to AXI4
   AXI4_Master_IFC #(Wd_Id, Wd_Addr, Wd_Data, Wd_User)
      dmem_AXI4_M <- mkAdapter_ReqRsp_AXI4 ("DMem AXI4 Adapter",
					    0,    // verbosity
					    cpu.fo_DMem_req,
					    cpu.fi_DMem_rsp);

   // A fabric for connecting CPU to {System, Near_Mem_IO
   Core_MMIO_Fabric_IFC  mmio_fabric <- mkCore_MMIO_Fabric;

   // Near_Mem_IO
   Near_Mem_IO_AXI4_IFC  clint <- mkNear_Mem_IO_AXI4;

   // ================================================================
   // Connect CPU to mmio fabric, and mmio fabric to CLINT

   // Connect CPU's memory interface to mmio fabric
   mkConnection (imem_AXI4_M,   mmio_fabric.v_from_masters [cpu_imem_master_num]);
   mkConnection (dmem_S_AXI4_M, mmio_fabric.v_from_masters [cpu_dmem_S_master_num]);
   mkConnection (dmem_AXI4_M,   mmio_fabric.v_from_masters [cpu_dmem_master_num]);

   // Targets on mmio fabric
   mkConnection (mmio_fabric.v_to_slaves [near_mem_io_target_num], clint.axi4_slave);
   //            mmio_fabric.v_to_slaves [default_target_num] lifted to module interface

   // ================================================================
   // Relay real-time from CLINT to CPU

   (* fire_when_enabled, no_implicit_conditions *)
   rule rl_relay_TIME;
      cpu.set_TIME (clint.mv_read_mtime);
   endrule

   // ================================================================
   // Post-reset initialization

   rule rl_first_init_start (rg_module_state == MODULE_STATE_INIT_0);
      mmio_fabric.reset;
      clint.server_reset.request.put (?);

      rg_module_state <= MODULE_STATE_INIT_1;

      if (verbosity != 0) begin
	 $display ("Catamaran_Core_Inner: start post-reset initializations ...");
	 $display ("    %m");
	 $display ("    %0d: rule rl_first_init_start", cur_cycle);
      end
   endrule

   rule rl_first_init_finish (rg_module_state == MODULE_STATE_INIT_1);
      let rsp2 <- clint.server_reset.response.get;

      clint.set_addr_map (zeroExtend (soc_map.m_near_mem_io_addr_base),
			  zeroExtend (soc_map.m_near_mem_io_addr_lim));

      let write_log <- $test$plusargs ("log");
      File f = InvalidFile;
      if (write_log) begin
	 $display ("INFO: Logfile is: log.txt");
	 f <- $fopen ("log.txt", "w");
      end
      else
	 $display ("INFO: No logfile");
      let init_params = Initial_Params {flog:           f,
					pc_reset_value: 'h_8000_0000,
					addr_base_mem:  'h_8000_0000,
					size_B_mem:     'h_1000_0000};

      cpu.init (init_params);
      spec_sto_buf.init (init_params);

      rg_module_state <= MODULE_STATE_READY;

      if (verbosity != 0) begin
	 $display ("Catamaran_Core_Inner: finish post-reset Initializations ...");
	 $display ("    %m");
	 $display ("    %0d: rule rl_first_init_finish", cur_cycle);
      end
   endrule

   // ================================================================
   // INTERFACE

   // ----------------------------------------------------------------
   // Interfaces that go directly out to AWSteria_Core_IFC

   // ----------------
   // AXI4 interfaces for memory, MMIO, and DMA
   // Note: DMA may or may not be coherent, depending on internal Core architecture.

   interface AXI4_Master_IFC mmio_M = mmio_fabric.v_to_slaves [default_target_num];

endmodule

// ================================================================

endpackage
