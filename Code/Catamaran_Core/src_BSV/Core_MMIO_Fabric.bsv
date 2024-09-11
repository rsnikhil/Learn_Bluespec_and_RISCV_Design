// Copyright (c) 2018-2024 Bluespec, Inc. All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Core_MMIO_Fabric;

// ================================================================
// Defines a specialization of AXI4 fabric used inside the Core to
// connect:
//     Initiators: CPU IMem, CPU DMem
//     Targets: System Interconnect, Near_Mem_IO (CLINT)

// ================================================================
// Project imports

// Main fabric
import AXI4_Types   :: *;
import AXI4_Fabric  :: *;
import Fabric_Defs  :: *;    // for Wd_Id, Wd_Addr, Wd_Data, Wd_User
import SoC_Map      :: *;

// ================================================================
// Fabric port numbers for Initiators

typedef 3  Core_MMIO_Fabric_Num_Initiators;

typedef Bit #(TLog #(Core_MMIO_Fabric_Num_Initiators))  Core_MMIO_Fabric_Initiator_Num;

Core_MMIO_Fabric_Initiator_Num  cpu_imem_master_num   = 0;    // IMem
Core_MMIO_Fabric_Initiator_Num  cpu_dmem_S_master_num = 1;    // speculative DMem
Core_MMIO_Fabric_Initiator_Num  cpu_dmem_master_num   = 2;    // non-speculative DMem

// ----------------
// Fabric port numbers for targets

typedef 2  Core_MMIO_Fabric_Num_Targets;

typedef Bit #(TLog #(Core_MMIO_Fabric_Num_Targets))  Core_MMIO_Fabric_Target_Num;

Core_MMIO_Fabric_Target_Num  default_target_num     = 0;
Core_MMIO_Fabric_Target_Num  near_mem_io_target_num = 1;    // MTIME, MTIMECMP, MSIP

// ----------------
// Specialization of parameterized AXI4 fabric for 1x2 Core fabric

typedef AXI4_Fabric_IFC #(Core_MMIO_Fabric_Num_Initiators,
			  Core_MMIO_Fabric_Num_Targets,
			  Wd_Id,
			  Wd_Addr,
			  Wd_Data,
			  Wd_User)  Core_MMIO_Fabric_IFC;

// ----------------

(* synthesize *)
module mkCore_MMIO_Fabric (Core_MMIO_Fabric_IFC);

   // System address map
   SoC_Map_IFC  soc_map  <- mkSoC_Map;

   // ----------------
   // Target address decoder
   // Any addr is legal, and there is only one target to service it.

   function Tuple2 #(Bool, Core_MMIO_Fabric_Target_Num)
            fn_addr_to_target_num  (Fabric_Addr addr);
      // Near_Mem_IO (CLINT)
      if (   (soc_map.m_near_mem_io_addr_base <= addr)
	  && (addr < soc_map.m_near_mem_io_addr_lim))
	 return tuple2 (True, near_mem_io_target_num);

      // Default: to System
      else
	 return tuple2 (True, default_target_num);
   endfunction

   AXI4_Fabric_IFC #(Core_MMIO_Fabric_Num_Initiators,
		     Core_MMIO_Fabric_Num_Targets,
		     Wd_Id, Wd_Addr, Wd_Data, Wd_User)
       fabric <- mkAXI4_Fabric (fn_addr_to_target_num);

   return fabric;
endmodule: mkCore_MMIO_Fabric

// ================================================================

endpackage
