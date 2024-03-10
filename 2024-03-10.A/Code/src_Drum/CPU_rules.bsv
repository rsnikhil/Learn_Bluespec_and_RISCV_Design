// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package CPU;

// ****************************************************************
// Top-level of unpipelined CPU.
// * State machine performing each of the "steps" of an instruction.
// * Lifts IMem and DMem connections up to next level up.

// ****************************************************************
// Imports from libraries

import FIFOF :: *;

// ----------------
// Imports from 'vendor' libs

import Cur_Cycle  :: *;
import Semi_FIFOF :: *;

// ----------------
// Local imports

import Utils       :: *;

import Arch        :: *;
import Instr_Bits  :: *;
import CSR_Bits    :: *;
import Mem_Req_Rsp :: *;
import Inter_Stage :: *;
import CPU_IFC     :: *;
import RISCV_GPRs  :: *;

// Functions for each step
import Fn_F       :: *;
import Fn_D       :: *;
import Fn_RR      :: *;

import Fn_EX_Control :: *;
import Fn_EX_Int     :: *;
import Fn_EX_DMem    :: *;

import Fn_Retire  :: *;

// ****************************************************************

String cpu_name = "Drum v0.6 2024-01-21";

// ****************************************************************
// The "steps" for each instruction

typedef enum {
   STEP_RESET,
   STEP_FETCH,       // Issue IMem request
   STEP_DECODE,      // Process IMem response
   STEP_RR,          // Register-read, and Control
   STEP_EX_CONTROL,  // Finish Branch, JAL, JALR, Illegals
   STEP_EX_INT,      // Integer ALU op
   STEP_DMEM_REQ,    // Send DMem request
   STEP_DMEM_RSP,    // Process DMem response
   STEP_RETIRE
   } CPU_State
deriving (Bits, Eq, FShow);

// ----------------------------------------------------------------

(* synthesize *)
module mkCPU (CPU_IFC);
   // ================================================================
   // STATE

   // Don't run until initialized
   Reg #(Bool) rg_running <- mkReg (False);

   // For debugging in simulation only
   Reg #(File) rg_flog <- mkReg (InvalidFile);

   Reg #(CPU_State)   rg_step <- mkReg (STEP_RESET);
   Reg #(Bit #(64))   rg_inum <- mkReg (0);    // For debugging only
   // The Program Counter
   Reg #(Bit #(XLEN)) rg_pc   <- mkReg (0);

   // The integer register file
   RISCV_GPRs_IFC #(XLEN)  gprs <- mkRISCV_GPRs_V;

   // Inter-step registers
   Reg #(F_to_D)                rg_F_to_D               <- mkRegU;
   Reg #(D_to_RR)               rg_D_to_RR              <- mkRegU;
   Reg #(RR_to_Retire)          rg_RR_to_Retire         <- mkRegU;

   Reg #(RR_to_EX_Control)      rg_RR_to_EX_Control     <- mkRegU;
   Reg #(EX_Control_to_Retire)  rg_EX_Control_to_Retire <- mkRegU;

   Reg #(RR_to_EX)              rg_RR_to_EX             <- mkRegU;
   Reg #(EX_to_Retire)          rg_EX_to_Retire         <- mkRegU;

   // Paths to and from memory
   FIFOF #(Mem_Req) f_IMem_req  <- mkFIFOF;
   FIFOF #(Mem_Rsp) f_IMem_rsp  <- mkFIFOF;

   FIFOF #(Mem_Req) f_DMem_req  <- mkFIFOF;
   FIFOF #(Mem_Rsp) f_DMem_rsp  <- mkFIFOF;

   // ================================================================
   // BEHAVIOR

   // ----------------
   // Issue IMem request (start instruction-fetch)

   rule rl_F (rg_step == STEP_FETCH);
      // The following are only for branch-prediction; not used in Drum
      let predicted_pc = 0;
      let epoch        = 0;

      let y <- fn_F (rg_inum, rg_pc, predicted_pc, epoch);
      rg_F_to_D <= y.to_D;
      f_IMem_req.enq (y.mem_req);
      rg_step <= STEP_DECODE;

      $fdisplay (rg_flog, "I_%0d ----------------", rg_inum);
      $fdisplay (rg_flog, "%0d: CPU.rl_F: ", cur_cycle, fshow_F_to_D (y.to_D));
      $fdisplay (rg_flog, "               ", fshow_Mem_Req (y.mem_req));
   endrule

   // ----------------
   // Process IMem reponse (finish instruction fetch)
   rule rl_D (rg_step == STEP_DECODE);
      let mem_rsp <- pop_o (to_FIFOF_O (f_IMem_rsp));
      let y       <- fn_D (rg_F_to_D, mem_rsp);
      rg_D_to_RR <= y;
      rg_step <= STEP_RR;

      $fdisplay (rg_flog, "%0d: CPU.rl_D: ", cur_cycle, fshow_D_to_RR (y));
   endrule

   // ----------------
   // Register-read, and dispatch
   rule rl_RR (rg_step == STEP_RR);
      // Read GPRs (assume: we've already checked scoreboard).
      // Ok that read_rs1 and read_rs2 may return junk values
      //         since not all instrs have rs1/rs2.
      let x       = rg_D_to_RR;
      let rs1_val = gprs.read_rs1 (instr_rs1 (x.instr));
      let rs2_val = gprs.read_rs2 (instr_rs2 (x.instr));

      Result_Dispatch y <- fn_Dispatch (rg_flog, x, rs1_val, rs2_val);

      rg_RR_to_Retire     <= y.to_Retire;
      rg_RR_to_EX_Control <= y.to_EX_Control;
      rg_RR_to_EX         <= y.to_EX;

      $fdisplay (rg_flog, "%0d: CPU.rl_RR: inum:%0d pc:%08h instr:%08h",
		 cur_cycle, x.inum, x.pc, x.instr);
      $fdisplay (rg_flog, "        rs1_val:%08h rs2_val:%08h", rs1_val, rs2_val);
      $fdisplay (rg_flog, "%0d: CPU.rl_RR: ", cur_cycle, fshow_RR_to_Retire (y.to_Retire));

      if (y.to_Retire.exec_tag == EXEC_TAG_RETIRE) begin
	 rg_step <= STEP_RETIRE;
	 $fdisplay (rg_flog, "    -> Retire (exception and SYSTEM): ");
      end
      else if (y.to_Retire.exec_tag == EXEC_TAG_CONTROL) begin
	 rg_step <= STEP_EX_CONTROL;
	 $fdisplay (rg_flog, "    -> EX_control: ",
		    fshow_RR_to_EX_Control (y.to_EX_Control));
      end
      else if (y.to_Retire.exec_tag == EXEC_TAG_INT) begin
	 rg_step <= STEP_EX_INT;
	 $fdisplay (rg_flog, "    -> EX_Int: ", fshow_RR_to_EX (y.to_EX));
      end
      else if (y.to_Retire.exec_tag == EXEC_TAG_DMEM) begin
	 rg_step <= STEP_DMEM_REQ;
	 $fdisplay (rg_flog, "    -> EX_DMem: ", fshow_RR_to_EX (y.to_EX));
      end
      else begin
	 $fdisplay (rg_flog, "    -> IMPOSSIBLE");
	 $finish (0);
      end
   endrule

   // ----------------
   // Do control ops (BRANCH/JAL/JALR)
   rule rl_EX_Control (rg_step == STEP_EX_CONTROL);
      let y <- fn_EX_Control (rg_flog, rg_RR_to_EX_Control);
      rg_EX_Control_to_Retire <= y;
      rg_step                 <= STEP_RETIRE;
      $fdisplay (rg_flog, "%0d: CPU.rl_EX_Control: ", cur_cycle,
		 fshow_EX_Control_to_Retire (y));
   endrule

   // ----------------
   // Do integer ops
   rule rl_EX_Int (rg_step == STEP_EX_INT);
      let y <- fn_EX_Int (rg_flog, rg_RR_to_EX);
      rg_EX_to_Retire <= y;
      rg_step         <= STEP_RETIRE;
      $fdisplay (rg_flog, "%0d: CPU.rl_Int: ", cur_cycle, fshow_EX_to_Retire (y));
   endrule

   // ----------------
   // Process DMem request
   rule rl_EX_DMem_Req (rg_step == STEP_DMEM_REQ);
      Mem_Req y <- fn_DMem_Req (rg_flog, rg_RR_to_EX);
      f_DMem_req.enq (y);
      rg_step <= STEP_DMEM_RSP;
      $fdisplay (rg_flog, "%0d: CPU.rl_DMem_Req:", cur_cycle, fshow_Mem_Req (y));
   endrule

   // ----
   // Process DMem response
   rule rl_EX_DMem_Rsp (rg_step == STEP_DMEM_RSP);
      let mem_rsp <- pop_o (to_FIFOF_O (f_DMem_rsp));
      let y       <- fn_DMem_Rsp (rg_flog, mem_rsp);
      rg_EX_to_Retire <= y;
      rg_step <= STEP_RETIRE;
      $fdisplay (rg_flog, "%0d: CPU.rl_DMem_Rsp:", cur_cycle);
      $fdisplay (rg_flog, "     ", fshow_Mem_Rsp (mem_rsp, (! is_STORE (y.instr))));
      $fdisplay (rg_flog, "     ", fshow_EX_to_Retire (y));
   endrule

   // ================================================================
   // Retire: merge incoming pipes and retire instr

   rule rl_Retire (rg_step == STEP_RETIRE);
      let y <- fn_Retire (rg_flog,
			  rg_RR_to_Retire,
			  rg_EX_Control_to_Retire,
			  rg_EX_to_Retire);
      if (y.exception) begin
	 $fwrite   (rg_flog, "%0d: CPU.rl_Retire:", cur_cycle);
	 $fwrite   (rg_flog, " Exception-handling not yet implemented:");
	 $fwrite   (rg_flog, " ", fshow_cause (y.cause));
	 $fdisplay (rg_flog, " %08h", y.exception_pc);
	 $fdisplay (rg_flog, " ", fshow (y));
	 $finish (1);
      end
      else begin
	 // Update PC, inum
	 rg_pc   <= y.to_F.next_pc;
	 rg_inum <= rg_inum + 1;
	 // Update Rd if has rd-result
	 if (y.to_RW.commit)
	    gprs.write_rd (y.to_RW.rd, y.to_RW.data);
      end
      rg_step <= STEP_FETCH;
   endrule

   // ================================================================
   // INTERFACE

   method Action init (Initial_Params initial_params);
      rg_flog    <= initial_params.flog;
      rg_pc      <= initial_params.pc_reset_value;
      rg_step    <= STEP_FETCH;
   endmethod

   interface fo_IMem_req = to_FIFOF_O (f_IMem_req);
   interface fi_IMem_rsp = to_FIFOF_I (f_IMem_rsp);

   interface fo_DMem_S_req    = dummy_FIFOF_O;
   interface fi_DMem_S_rsp    = dummy_FIFOF_I;
   interface fo_DMem_S_commit = dummy_FIFOF_O;

   interface fo_DMem_req = to_FIFOF_O (f_DMem_req);
   interface fi_DMem_rsp = to_FIFOF_I (f_DMem_rsp);
endmodule

// ****************************************************************

endpackage
