// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package IALU;

// ****************************************************************
// Imports from libraries

import Cur_Cycle :: *;

// ----------------
// Local imports

import Utils      :: *;
import Arch       :: *;
import Instr_Bits :: *;

// ****************************************************************

Integer verbosity = 0;

// ****************************************************************
// Integer ALU
// TODO: the opcode/funct3/funct7 tests here can be greatly optimized

// This is actually a pure function; is ActionValue only to allow
// $display insertion for debugging
function ActionValue #(Bit #(XLEN))
         fn_IALU (Bit #(32)    instr,
		  Bit #(XLEN)  v1,
		  Bit #(XLEN)  v2,
		  Bit #(32)    imm,

		  File logf);
   actionvalue
      Bit #(7)    opcode = instr_opcode (instr);
      Bit #(3)    funct3 = instr_funct3 (instr);
      // Signed int versions of v1, v2 and imm
      Int #(XLEN) iv1    = unpack (v1);
      Int #(XLEN) iv2    = unpack (v2);
      Int #(XLEN) i_imm  = unpack (imm);

      Bool implemented = False;    // for debugging only

      Bit #(XLEN) y_OP     = 0;
      if (opcode == opcode_OP) begin

	 implemented = True;    // Debugging

	 Bit #(6) shamt = (v2 [5:0] & ((xlen == 32) ? 'h1F : 'h3F));
	 case (funct3)
	    funct3_ADD:  y_OP = pack ((instr [30] == 1'b0)
				      ? (iv1 + iv2)
				      : (iv1 - iv2));
	    funct3_SLL:  y_OP = v1 << shamt;
	    funct3_SLT:  y_OP = ((iv1 < iv2) ? 1 : 0);
	    funct3_SLTU: y_OP = ((v1  < v2)  ? 1 : 0);
	    funct3_XOR:  y_OP = v1 ^ v2;
	    funct3_SRL:  // Note: funct3_SRL == funct3_SRA; distinguish on instr [30]
	                 y_OP = ((instr [30] == 1'b0)
				 ? v1 >> shamt                // SRL
				 : pack (iv1 >> shamt));      // SRA
	    funct3_OR:   y_OP = v1 | v2;
	    funct3_AND:  y_OP = v1 & v2;

	    default:     implemented = False;    // Debugging

	 endcase
	 if (verbosity != 0)
	    wr_log (logf,
		    $format ("fn_IALU (%0d/0x%0h) <= (%0d/0x%0h) OP (%0d/0x%0h)",
			     y_OP, y_OP, iv1, iv1, iv2, iv2));
      end

      Bit #(XLEN) y_OP_IMM = 0;
      if (opcode == opcode_OP_IMM) begin

	 implemented = True;    // Debugging

	 Bit #(6) shamt = (imm [5:0] & ((xlen == 32) ? 'h1F : 'h3F));
	 case (funct3)
	    funct3_ADDI:  y_OP_IMM = pack (iv1 + i_imm);
	    funct3_SLTI:  y_OP_IMM = ((iv1 < i_imm) ? 1 : 0);
	    funct3_SLTIU: y_OP_IMM = ((v1  < imm)   ? 1 : 0);
	    funct3_XORI:  y_OP_IMM = v1 ^ imm;
	    funct3_ORI:   y_OP_IMM = v1 | imm;
	    funct3_ANDI:  y_OP_IMM = v1 & imm;
	    funct3_SLLI:  y_OP_IMM = v1 << shamt;
	    funct3_SRLI:  // Note: funct3_SRLI == funct3_SRAI; distinguish on instr [30]
	                  y_OP_IMM = ((instr [30] == 1'b0)
				      ? (v1 >> shamt)          // SRLI
				      : pack (iv1 >> shamt));  // SRAI

	    default:      implemented = False;    // Debugging

	 endcase
	 if (verbosity != 0)
	    wr_log (logf,
		    $format ("fn_IALU (%0d/0x%0h) <= (%0d/0x%0h) OP_IMM (%0d/0x%0h)",
			     y_OP_IMM, y_OP_IMM, iv1, iv1, iv2, iv2));
      end

      Bit #(XLEN) result = y_OP | y_OP_IMM;

      // DEBUGGING
      if (! implemented) begin
	 wr_log2 (logf, $format ("ERROR: fn_IALU: UNIMPLEMENTED: instr:", instr));
	 $finish (1);
      end

      return result;
   endactionvalue
endfunction

// ****************************************************************

endpackage
