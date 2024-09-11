// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package CPU_IFC;

// ****************************************************************
// Common interface for both pipelined and unpipelined CPUs

// ****************************************************************
// Imports from libraries

import FIFOF :: *;

// ----------------
// Imports from 'vendor' libs

import Semi_FIFOF :: *;

// ----------------
// Local imports

import Utils       :: *;
import Mem_Req_Rsp :: *;
import Inter_Stage :: *;

// ****************************************************************

interface CPU_IFC;
   method Action init (Initial_Params initial_params);

   // IMem
   interface FIFOF_O #(Mem_Req) fo_IMem_req;
   interface FIFOF_I #(Mem_Rsp) fi_IMem_rsp;

   // DMem, speculative
   interface FIFOF_O #(Mem_Req) fo_DMem_S_req;
   interface FIFOF_I #(Mem_Rsp) fi_DMem_S_rsp;
   interface FIFOF_O #(Retire_to_DMem_Commit)  fo_DMem_S_commit;

   // DMem, non-speculative
   interface FIFOF_O #(Mem_Req) fo_DMem_req;
   interface FIFOF_I #(Mem_Rsp) fi_DMem_rsp;

   // Set TIME
   (* always_ready, always_enabled *)
   method Action set_TIME (Bit #(64) t);

   // Debugger support
   // Requests from/responses to remote debugger
   interface FIFOF_I #(Dbg_to_CPU_Pkt)   fi_dbg_to_CPU_pkt;
   interface FIFOF_O #(Dbg_from_CPU_Pkt) fo_dbg_from_CPU_pkt;
   // Memory requests/responses for remote debugger
   interface FIFOF_O #(Mem_Req) fo_dbg_to_mem_req;
   interface FIFOF_I #(Mem_Rsp) fi_dbg_from_mem_rsp;
endinterface

// ****************************************************************

endpackage
