// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Fn_Decode;

// ****************************************************************
// Decode function
// * Check that instruction is legal, and note if it uses rs1/rs2/rd

// ****************************************************************
// Imports from libraries

// None

// ----------------
// Local imports

import Utils       :: *;
import Instr_Bits  :: *;
import CSR_Bits    :: *;
import Mem_Req_Rsp :: *;
import Inter_Stage :: *;

// ****************************************************************
// Decode: Functionality

// This is actually a pure function; is ActionValue only to allow $display insertion
function ActionValue #(Decode_to_RR)
         fn_Decode (Fetch_to_Decode  x_F_to_D,
		    Mem_Rsp          rsp_IMem,

		    File             flog);
   actionvalue
      Bit #(32) instr = truncate (rsp_IMem.data);
      Bit #(5)  rd    = instr_rd (instr);

      let fallthru_pc = x_F_to_D.pc + 4;

      // Baseline info to next stage
      let y = Decode_to_RR {pc:           x_F_to_D.pc,

			    exception:    False,
			    cause:        ?,
			    tval:         0,

			    // not-exception
			    fallthru_pc:  fallthru_pc,
			    instr:        instr,
			    opclass:      ?,
			    has_rs1:      False,
			    has_rs2:      False,
			    has_rd:       False,
			    writes_mem:   False,
			    imm:          0,
			    predicted_pc: x_F_to_D.predicted_pc,
			    epoch:        x_F_to_D.epoch,
			    inum:         x_F_to_D.inum};

      Bool non_zero_rd = (rd != 0);

      if (rsp_IMem.rsp_type == MEM_RSP_MISALIGNED) begin
	 y.exception = True;
	 y.cause     = cause_INSTRUCTION_ADDRESS_MISALIGNED;
	 y.tval      = truncate (rsp_IMem.addr);
      end
      else if (rsp_IMem.rsp_type == MEM_RSP_ERR) begin
	 y.exception = True;
	 y.cause     = cause_INSTRUCTION_ACCESS_FAULT;
	 y.tval      = truncate (rsp_IMem.addr);
      end
      else if (rsp_IMem.rsp_type == MEM_REQ_DEFERRED) begin
	 // IMPOSSIBLE: DEFERRED only used for speculative EX DMem MMIO
	 Fmt fmt = $format ("fn_D: IMPOSSIBLE: IMem response is DEFERRED\n");
	 fmt = fmt + fshow_Mem_Rsp (rsp_IMem, True);
	 wr_log2 (flog, fmt);
      end
      else if (is_legal_LUI (instr) || is_legal_AUIPC (instr)) begin
	 y.opclass = OPCLASS_INT;
	 y.has_rd  = non_zero_rd;
	 y.imm     = signExtend ({ instr_imm_U (instr), 12'h000 });
      end
      else if (is_legal_BRANCH (instr)) begin
	 y.opclass = OPCLASS_CONTROL;
	 y.has_rs1 = True;
	 y.has_rs2 = True;
	 y.imm     = signExtend (instr_imm_B (instr));
      end
      else if (is_legal_JAL (instr)) begin
	 y.opclass = OPCLASS_CONTROL;
	 y.has_rd  = non_zero_rd;
	 y.imm     = signExtend (instr_imm_J (instr));
      end
      else if (is_legal_JALR (instr)) begin
	 y.opclass = OPCLASS_CONTROL;
	 y.has_rs1 = True;
	 y.has_rd  = non_zero_rd;
	 y.imm     = signExtend (instr_imm_I (instr));
      end
      else if (is_legal_LOAD (instr)) begin
	 y.opclass = OPCLASS_MEM;
	 y.has_rs1 = True;
	 y.has_rd  = non_zero_rd;
	 y.imm     = signExtend (instr_imm_I (instr));
      end
      else if (is_legal_STORE (instr)) begin
	 y.opclass    = OPCLASS_MEM;
	 y.has_rs1    = True;
	 y.has_rs2    = True;
	 y.writes_mem = True;
	 y.imm        = signExtend (instr_imm_S (instr));
      end
      else if (is_legal_OP_IMM (instr)) begin
	 y.opclass = OPCLASS_INT;
	 y.has_rs1 = True;
	 y.has_rd  = non_zero_rd;
	 y.imm     = signExtend (instr_imm_I (instr));
      end
      else if (is_legal_OP (instr)) begin
	 y.opclass = OPCLASS_INT;
	 y.has_rs1 = True;
	 y.has_rs2 = True;
	 y.has_rd  = non_zero_rd;
      end
      else if (is_legal_ECALL (instr)
	       || is_legal_EBREAK (instr)
	       || is_legal_MRET (instr)) begin
         y.opclass = OPCLASS_SYSTEM;
      end
      else if (is_legal_CSRRxx (instr)) begin
	 y.opclass = OPCLASS_SYSTEM;
	 y.has_rs1 = (instr_funct3 (instr) [2] == 0);
	 y.has_rd  = non_zero_rd;
      end
      else if (is_legal_FENCE (instr)) begin
	 y.opclass = OPCLASS_FENCE;
      end
      else if (is_legal_FENCE_I (instr)) begin
	 y.opclass = OPCLASS_FENCE;
      end
      else begin
	 y.exception = True;
	 y.cause     = cause_ILLEGAL_INSTRUCTION;
	 y.tval      = truncate (instr);
      end

      return y;
   endactionvalue
endfunction

// ****************************************************************
// Logging actions

function Action log_Decode (File flog, Decode_to_RR y, Mem_Rsp rsp_IMem);
   action
      wr_log (flog, ($format("CPU.Decode:\n    ")
		     + fshow_Decode_to_RR (y) + $format ("\n    ")
		     + fshow_Mem_Rsp (rsp_IMem, True)));
      ftrace (flog, y.inum, y.pc, y.instr, "D", $format(""));
   endaction
endfunction

// ****************************************************************

endpackage
