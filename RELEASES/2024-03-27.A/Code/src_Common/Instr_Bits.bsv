// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Instr_Bits;

// ****************************************************************
// Bit encodings/decodings of RISC-V instructions

// ****************************************************************

import Arch :: *;

// ****************************************************************
// Instruction fields

// ----------------
// Instruction "quadrant": 00,01,10 for 16-bit instrs (C extension), 11 for 32-bit instrs

Bit #(2) quadrant_C0 = 2'b00;
Bit #(2) quadrant_C1 = 2'b01;
Bit #(2) quadrant_C2 = 2'b10;
Bit #(2) quadrant_C3 = 2'b11;

function Bit #(2) instr_quadrant (Bit #(32) instr);
   return instr [1:0];
endfunction

// ----------------
// Opcodes

function Bit #(7) instr_opcode (Bit #(32) instr);
   return instr [6:0];
endfunction

function Bit #(3) instr_funct3 (Bit #(32) instr);
   return instr [14:12];
endfunction

function Bit #(7) instr_funct7 (Bit #(32) instr);
   return instr [31:25];
endfunction

// ----------------
// Sources and destinations

function Bit #(5) instr_rs1 (Bit #(32) instr);
   return instr [19:15];
endfunction

function Bit #(5) instr_rs2 (Bit #(32) instr);
   return instr [24:20];
endfunction

function Bit #(5) instr_rd (Bit #(32) instr);
   return instr [11:7];
endfunction

// ----------------
// Immediates

function Bit #(12) instr_imm_I (Bit #(32) instr);
   return instr [31:20];
endfunction

function Bit #(12) instr_imm_S (Bit #(32) instr);
   // instr [31:25] = imm [11:5]    instr [11:7] = imm [4:0]

   Bit #(7)  offset_11_5 = instr [31:25];
   Bit #(5)  offset_4_0  = instr [11:7];

   return { offset_11_5, offset_4_0 };
endfunction

function Bit #(13) instr_imm_B (Bit #(32) instr);
   // instr [31:25] = offset[12|10:5]    instr [11:7] = offset[4:1|11]
   Bit #(1)  offset_12   = instr [31];
   Bit #(6)  offset_10_5 = instr [30:25];
   Bit #(4)  offset_4_1  = instr [11:8];
   Bit #(1)  offset_11   = instr [7];

   return { offset_12, offset_11, offset_10_5, offset_4_1, 1'b0 };
endfunction

function Bit #(20) instr_imm_U (Bit #(32) instr);
   return instr [31:12];
endfunction

function Bit #(21) instr_imm_J (Bit #(32) instr);
   // instr [31:12] = imm[20|10:1|11|19:12]
   Bit #(1)  imm_20    = instr [31];
   Bit #(10) imm_10_1  = instr [30:21];
   Bit #(1)  imm_11    = instr [20];
   Bit #(8)  imm_19_12 = instr [19:12];

   return { imm_20, imm_19_12, imm_11, imm_10_1, 1'b0 };
endfunction

// ****************************************************************
// Legal instructions

// ----------------
// RV32 and RV64

Bit #(7) opcode_LUI = 7'b_011_0111;

function Bool is_legal_LUI (Bit #(32) instr);
   return (instr_opcode (instr) == 7'b_011_0111);
endfunction

// ----------------
// RV32 and RV64

Bit #(7) opcode_AUIPC = 7'b_001_0111;

function Bool is_legal_AUIPC (Bit #(32) instr);
   return (instr_opcode (instr) == opcode_AUIPC);
endfunction

// ----------------
// RV32 and RV64

Bit #(7) opcode_JAL = 7'b_110_1111;

function Bool is_legal_JAL (Bit #(32) instr);
   return (instr_opcode (instr) == opcode_JAL);
endfunction

// ----------------
// RV32 and RV64

Bit #(7) opcode_JALR = 7'b_110_0111;

function Bool is_legal_JALR (Bit #(32) instr);
   return ((instr_opcode (instr) == opcode_JALR)
	   && (instr_funct3 (instr) == 3'b000));
endfunction

// ----------------
// RV32 and RV64

Bit #(7) opcode_BRANCH = 7'b_110_0011;

Bit #(3) funct3_BEQ  = 3'b_000;
Bit #(3) funct3_BNE  = 3'b_001;
Bit #(3) funct3_BLT  = 3'b_100;
Bit #(3) funct3_BGE  = 3'b_101;
Bit #(3) funct3_BLTU = 3'b_110;
Bit #(3) funct3_BGEU = 3'b_111;

function Bool is_legal_BRANCH (Bit #(32) instr);
   let funct3 = instr_funct3 (instr);
   return ((instr_opcode (instr) == opcode_BRANCH)
	   && (funct3 != 3'b010)
	   && (funct3 != 3'b011));
endfunction

// ----------------
// RV32 and RV64
// Note LWU and LD are RV64 only

Bit #(7) opcode_LOAD = 7'b_000_0011;

Bit #(3) funct3_LB  = 3'b_000;
Bit #(3) funct3_LH  = 3'b_001;
Bit #(3) funct3_LW  = 3'b_010;
Bit #(3) funct3_LBU = 3'b_100;
Bit #(3) funct3_LHU = 3'b_101;

Bit #(3) funct3_LWU = 3'b_111;    // RV64 only
Bit #(3) funct3_LD  = 3'b_011;    // RV64 only

function Bool is_legal_LOAD (Bit #(32) instr);
   let funct3 = instr_funct3 (instr);
   return ((instr_opcode (instr) == opcode_LOAD)
	   && (  (funct3 == funct3_LB)
	      || (funct3 == funct3_LH)
	      || (funct3 == funct3_LW)
	      || (funct3 == funct3_LBU)
	      || (funct3 == funct3_LHU)
	      || ((funct3 == funct3_LWU) && (xlen == 64))
	      || ((funct3 == funct3_LD) && (xlen == 64))));
endfunction

// ----------------
// RV32 and RV64
// Note SD is RV64 only

Bit #(7) opcode_STORE = 7'b_010_0011;

Bit #(3) funct3_SB  = 3'b_000;
Bit #(3) funct3_SH  = 3'b_001;
Bit #(3) funct3_SW  = 3'b_010;
Bit #(3) funct3_SD  = 3'b_011;    // RV64 only

function Bool is_legal_STORE (Bit #(32) instr);
   let funct3 = instr_funct3 (instr);
   return ((instr_opcode (instr) == opcode_STORE)
	   && (  (funct3 == funct3_SB)
	      || (funct3 == funct3_SH)
	      || (funct3 == funct3_SW)
	      || ((funct3 == funct3_SD) && (xlen == 64))));
endfunction

// ----------------
// RV32 and RV64

Bit #(7) opcode_AMO = 7'b_010_1111;

Bit #(3) funct3_W  = 3'b_010;
Bit #(3) funct3_D  = 3'b_011;    // RV64 only

Bit #(5) funct5_LR      = 5'b_00010;
Bit #(5) funct5_SC      = 5'b_00011;
Bit #(5) funct5_AMOSWAP = 5'b_00001;
Bit #(5) funct5_AMOADD  = 5'b_00000;
Bit #(5) funct5_AMOXOR  = 5'b_00100;
Bit #(5) funct5_AMOAND  = 5'b_01100;
Bit #(5) funct5_AMOOR   = 5'b_01000;
Bit #(5) funct5_AMOMIN  = 5'b_10000;
Bit #(5) funct5_AMOMAX  = 5'b_10100;
Bit #(5) funct5_AMOMINU = 5'b_11000;
Bit #(5) funct5_AMOMAXU = 5'b_11100;

// The following are pseudo funct5s for ordinary LOAD/STORE and FENCE
// used in Mem_Req
Bit #(5) funct5_LOAD    = 5'b_11110;
Bit #(5) funct5_STORE   = 5'b_11111;
Bit #(5) funct5_FENCE   = 5'b_11101;
Bit #(5) funct5_BOGUS   = 5'b_00101;

function Bool is_legal_AMO (Bit #(32) instr);
   let funct3 = instr_funct3 (instr);
   let funct5 = instr [31:27];
   return ((instr_opcode (instr) == opcode_AMO)
	   && (  (funct3 == funct3_W)
	      || ((funct3 == funct3_D) && (xlen == 64)))
	   && ((funct5 == funct5_LR)
	       || (funct5 == funct5_SC)
	       || (funct5 == funct5_AMOSWAP)
	       || (funct5 == funct5_AMOADD)
	       || (funct5 == funct5_AMOXOR)
	       || (funct5 == funct5_AMOAND)
	       || (funct5 == funct5_AMOOR)
	       || (funct5 == funct5_AMOMIN)
	       || (funct5 == funct5_AMOMAX)
	       || (funct5 == funct5_AMOMINU)
	       || (funct5 == funct5_AMOMAXU)));
endfunction

// ----------------
// RV32 and RV64

Bit #(7) opcode_OP = 7'b_011_0011;

Bit #(7) funct7_ADD  = 7'b_000_0000;    Bit #(3) funct3_ADD  = 3'b_000;
Bit #(7) funct7_SUB  = 7'b_010_0000;    Bit #(3) funct3_SUB  = 3'b_000;
Bit #(7) funct7_SLL  = 7'b_000_0000;    Bit #(3) funct3_SLL  = 3'b_001;
Bit #(7) funct7_SLT  = 7'b_000_0000;    Bit #(3) funct3_SLT  = 3'b_010;
Bit #(7) funct7_SLTU = 7'b_000_0000;    Bit #(3) funct3_SLTU = 3'b_011;
Bit #(7) funct7_XOR  = 7'b_000_0000;    Bit #(3) funct3_XOR  = 3'b_100;
Bit #(7) funct7_SRL  = 7'b_000_0000;    Bit #(3) funct3_SRL  = 3'b_101;
Bit #(7) funct7_SRA  = 7'b_010_0000;    Bit #(3) funct3_SRA  = 3'b_101;
Bit #(7) funct7_OR   = 7'b_000_0000;    Bit #(3) funct3_OR   = 3'b_110;
Bit #(7) funct7_AND  = 7'b_000_0000;    Bit #(3) funct3_AND  = 3'b_111;

function Bool is_legal_OP (Bit #(32) instr);
   let funct3 = instr_funct3 (instr);
   let funct7 = instr_funct7 (instr);
   return ((instr_opcode (instr) == opcode_OP)
	   && (  (funct3 == funct3_ADD)  && (funct7 == funct7_ADD)
	      || (funct3 == funct3_SUB)  && (funct7 == funct7_SUB)
	      || (funct3 == funct3_SLL)  && (funct7 == funct7_SLL)
	      || (funct3 == funct3_SLT)  && (funct7 == funct7_SLT)
	      || (funct3 == funct3_SLTU) && (funct7 == funct7_SLTU)
	      || (funct3 == funct3_XOR)  && (funct7 == funct7_XOR)
	      || (funct3 == funct3_SRL)  && (funct7 == funct7_SRL)
	      || (funct3 == funct3_SRA)  && (funct7 == funct7_SRA)
	      || (funct3 == funct3_OR)   && (funct7 == funct7_OR)
	      || (funct3 == funct3_AND)  && (funct7 == funct7_AND)));
endfunction

// ----------------
// RV32 and RV64
// Note: SLLI and SRxI have slightly different funct7 in RV32 and RV64

Bit #(7) opcode_OP_IMM = 7'b_001_0011;

Bit #(3) funct3_ADDI  = 3'b_000;
Bit #(3) funct3_SLTI  = 3'b_010;
Bit #(3) funct3_SLTIU = 3'b_011;
Bit #(3) funct3_XORI  = 3'b_100;
Bit #(3) funct3_ORI   = 3'b_110;
Bit #(3) funct3_ANDI  = 3'b_111;
Bit #(3) funct3_SLLI  = 3'b_001;

// Note: funct3 is the same for the following
Bit #(3) funct3_SRLI  = 3'b_101;
Bit #(3) funct3_SRAI  = 3'b_101;
Bit #(3) funct3_SRxI  = 3'b_101;

function Bool is_legal_OP_IMM (Bit #(32) instr);
   let funct3 = instr_funct3 (instr);
   let funct7 = instr_funct7 (instr);
   Bool is_legal_SLLI = (((xlen == 32) && (funct7 == 7'b000_0000))
			 || ((xlen == 64) && (funct7 [6:1] == 6'b0)));
   Bool is_legal_SRxI = ((   (xlen == 32) && ((funct7 == 7'b010_0000)
                                              || (funct7 == 7'b000_0000)))
			 || ((xlen == 64) && ((funct7 [6:1] == 6'b01_0000)
                                              || (funct7 [6:1] == 6'b00_0000))));
   return ((instr_opcode (instr) == opcode_OP_IMM)
	   && ((funct3 == funct3_SLLI)
	      ? is_legal_SLLI
	       : ((funct3 == funct3_SRxI)
		  ? is_legal_SRxI
		  : True)));
endfunction

// ----------------
// RV64 only

Bit #(7) opcode_OP_32 = 7'b_011_1011;

Bit #(7) funct7_ADDW = 7'b_000_0000;    Bit #(3) funct3_ADDW = 3'b_000;
Bit #(7) funct7_SUBW = 7'b_010_0000;    Bit #(3) funct3_SUBW = 3'b_000;
Bit #(7) funct7_SLLW = 7'b_000_0000;    Bit #(3) funct3_SLLW = 3'b_001;
Bit #(7) funct7_SRLW = 7'b_000_0000;    Bit #(3) funct3_SRLW = 3'b_101;
Bit #(7) funct7_SRAW = 7'b_010_0000;    Bit #(3) funct3_SRAW = 3'b_101;

function Bool is_legal_OP_32 (Bit #(32) instr);
   let funct7 = instr_funct7 (instr);
   let funct3 = instr_funct3 (instr);
   return ((instr_opcode (instr) == opcode_OP_32)
	   && (xlen == 64)
	   && (  ((funct3 == funct3_ADDW)  && (funct7 == funct7_ADDW))
	      || ((funct3 == funct3_SUBW)  && (funct7 == funct7_SUBW))
	      || ((funct3 == funct3_SLLW)  && (funct7 == funct7_SLLW))
	      || ((funct3 == funct3_SRLW)  && (funct7 == funct7_SRLW))
	      || ((funct3 == funct3_SRAW)  && (funct7 == funct7_SRAW))));
endfunction

// ----------------
// RV64 only

Bit #(7) opcode_OP_IMM_32 = 7'b_001_1011;

                                         Bit #(3) funct3_ADDIW = 3'b_000;
Bit #(7) funct7_SLLIW = 7'b_000_0000;    Bit #(3) funct3_SLLIW = 3'b_001;
Bit #(7) funct7_SRLIW = 7'b_000_0000;    Bit #(3) funct3_SRLIW = 3'b_101;
Bit #(7) funct7_SRAIW = 7'b_010_0000;    Bit #(3) funct3_SRAIW = 3'b_101;

function Bool is_legal_OP_IMM_32 (Bit #(32) instr);
   let funct3 = instr_funct3 (instr);
   let funct7 = instr_funct7 (instr);
   return ((instr_opcode (instr) == opcode_OP_IMM_32)
	   && (xlen == 64)
	   && (  (funct3 == funct3_ADDIW)
	      || ((funct3 == funct3_SLLIW)  && (funct7 == funct7_SLLIW))
	      || ((funct3 == funct3_SRLIW)  && (funct7 == funct7_SRLIW))
	      || ((funct3 == funct3_SRAIW)  && (funct7 == funct7_SRAIW))));
endfunction

// ----------------
// RV32 and RV64

Bit #(7) opcode_MISC_MEM = 7'b_000_1111;

Bit #(3) funct3_FENCE   = 3'b_000;
Bit #(3) funct3_FENCE_I = 3'b_001;

function Bool is_legal_FENCE (Bit #(32) instr);
   let funct3 = instr_funct3 (instr);
   return ((instr_opcode (instr) == opcode_MISC_MEM) && (funct3 == funct3_FENCE));
endfunction

function Bool is_legal_FENCE_I (Bit #(32) instr);
   let funct3 = instr_funct3 (instr);
   return ((instr_opcode (instr) == opcode_MISC_MEM) && (funct3 == funct3_FENCE_I));
endfunction

// ----------------
// RV32 and RV64

Bit #(7) opcode_SYSTEM = 7'b_111_0011;

function Bool is_legal_ECALL (Bit #(32) instr);
   let imm_I  = instr_imm_I (instr);
   let rs1    = instr_rs1 (instr);
   let funct3 = instr_funct3 (instr);
   let rd     = instr_rd (instr);
   return ((instr_opcode (instr) == opcode_SYSTEM)
	   && (imm_I  == 12'b0)
	   && (rs1    == 0)
	   && (funct3 == 0)
	   && (rd     == 0));
endfunction

function Bool is_legal_EBREAK (Bit #(32) instr);
   let imm_I  = instr_imm_I (instr);
   let rs1    = instr_rs1 (instr);
   let funct3 = instr_funct3 (instr);
   let rd     = instr_rd (instr);
   return ((instr_opcode (instr) == opcode_SYSTEM)
	   && (imm_I  == 12'b1)
	   && (rs1    == 0)
	   && (funct3 == 0)
	   && (rd     == 0));
endfunction

function Bool is_legal_MRET (Bit #(32) instr);
   let imm_I  = instr_imm_I (instr);
   let rs1    = instr_rs1 (instr);
   let funct3 = instr_funct3 (instr);
   let rd     = instr_rd (instr);
   return ((instr_opcode (instr) == opcode_SYSTEM)
	   && (imm_I  == 12'b_0011_0000_0010)
	   && (rs1    == 0)
	   && (funct3 == 0)
	   && (rd     == 0));
endfunction

function Bool is_legal_CSRRxx (Bit #(32) instr);
   let funct3 = instr_funct3 (instr);
   return ((instr_opcode (instr) == opcode_SYSTEM)
	   && (funct3 != 0)
	   && (funct3 != 4));
endfunction

function Bool is_CSRRxI (Bit #(32) instr);
   return (instr [14] == 1'b1);
endfunction

function Bool is_CSRRWx (Bit #(32) instr);
   return (instr [13:12] == 2'b01);
endfunction

function Bool is_CSRRSx (Bit #(32) instr);
   return (instr [13:12] == 2'b10);
endfunction

function Bool is_CSRRCx (Bit #(32) instr);
   return (instr [13:12] == 2'b11);
endfunction

// ****************************************************************
// The following are cheaper opcode tests, assuming instr is legal

function Bit #(5) instr_opcode_5b (Bit #(32) instr);
   return instr [6:2];
endfunction

function Bool is_LUI (Bit #(32) instr);
   return (instr_opcode_5b (instr) == opcode_LUI [6:2]);
endfunction

function Bool is_AUIPC (Bit #(32) instr);
   return (instr_opcode_5b (instr) == opcode_AUIPC [6:2]);
endfunction

function Bool is_JAL (Bit #(32) instr);
   return (instr_opcode_5b (instr) == opcode_JAL [6:2]);
endfunction

function Bool is_JALR (Bit #(32) instr);
   return (instr_opcode_5b (instr) == opcode_JALR [6:2]);
endfunction

function Bool is_BRANCH (Bit #(32) instr);
   return (instr_opcode_5b (instr) == opcode_BRANCH [6:2]);
endfunction

function Bool is_LOAD (Bit #(32) instr);
   return (instr_opcode_5b (instr) == opcode_LOAD [6:2]);
endfunction

function Bool is_STORE (Bit #(32) instr);
   return (instr_opcode_5b (instr) == opcode_STORE [6:2]);
endfunction

function Bool is_AMO (Bit #(32) instr);
   return (instr_opcode_5b (instr) == opcode_AMO [6:2]);
endfunction

function Bool is_FENCE (Bit #(32) instr);
   return is_legal_FENCE (instr);
endfunction

function Bool is_LR (Bit #(32) instr);
   return (is_AMO (instr) && (instr [31:27] == funct5_LR));
endfunction

function Bool is_OP (Bit #(32) instr);
   return (instr_opcode_5b (instr) == opcode_OP [6:2]);
endfunction

function Bool is_OP_IMM (Bit #(32) instr);
   return (instr_opcode_5b (instr) == opcode_OP_IMM [6:2]);
endfunction

function Bool is_OP_32 (Bit #(32) instr);
   return (instr_opcode_5b (instr) == opcode_OP_32 [6:2]);
endfunction

function Bool is_OP_IMM_32 (Bit #(32) instr);
   return (instr_opcode_5b (instr) == opcode_OP_IMM_32 [6:2]);
endfunction

// ****************************************************************

endpackage
