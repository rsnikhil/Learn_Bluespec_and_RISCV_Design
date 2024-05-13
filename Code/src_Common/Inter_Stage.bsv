// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package Inter_Stage;

// ****************************************************************
// Imports from libraries

import Vector :: *;

// ----------------
// Local imports

import Arch       :: *;
import Instr_Bits :: *;
import CSR_Bits   :: *;

// ****************************************************************
// Pipeline forward flow

typedef 2              W_Epoch;
typedef Bit #(W_Epoch) Epoch;

// ================================================================
// Fetch => Decode

typedef struct {
   Bit #(XLEN)  pc;

   Bit #(XLEN)  predicted_pc;    // Fife only: for branch-prediction
   Epoch        epoch;           // Fife only: for branch-prediction

   Bit #(64)    inum;            // for debugging only
} Fetch_to_Decode
deriving (Bits, FShow);

// ================================================================
// Decode => Register Read

typedef enum {OPCLASS_SYSTEM,     // EBREAK, ECALL, CSRRxx
              OPCLASS_CONTROL,    // BRANCH, JAL, JALR
	      OPCLASS_INT,
	      OPCLASS_MEM,        // LOAD, STORE, AMO
	      OPCLASS_FENCE}      // FENCE
OpClass
deriving (Bits, Eq, FShow);

typedef struct {Bit #(XLEN)  pc;

		Bool         exception;  // Fetch exception/ decode illegal instr
		Bit #(4)     cause;
		Bit #(XLEN)  tval;

		// If not exception
		Bit #(XLEN)  fallthru_pc;
		Bit #(32)    instr;
                OpClass      opclass;
		Bool         has_rs1;
		Bool         has_rs2;
		Bool         has_rd;
		Bool         writes_mem;   // All mem ops other than LOAD
		Bit #(XLEN)  imm;          // Canonical (bit-swizzled)

		Bit #(XLEN)  predicted_pc; // For branch-prediction only
		Epoch        epoch;        // For branch-prediction only
		Bit #(64)    inum;
} Decode_to_RR
deriving (Bits, FShow);

// ================================================================
// Register Read => Retire Direct
// Controls Retire's merge of results from execution pipelines

typedef enum {EXEC_TAG_DIRECT,
	      EXEC_TAG_CONTROL,
	      EXEC_TAG_INT,
	      EXEC_TAG_DMEM
} Exec_Tag
deriving (Bits, Eq, FShow);


typedef struct {Exec_Tag     exec_tag;    // ``flow'' for this instr

		Bit #(XLEN)  pc;
		Bool         has_rd;      // From RR
		Bool         writes_mem;  // From RR

		Bool         exception;   // Fetch exception, decode illegal instr
		Bit #(4)     cause;
		Bit #(XLEN)  tval;

		// If not exception
		Bit #(32)    instr;
		Bit #(XLEN)  fallthru_pc;
		Bit #(XLEN)  rs1_val;     // For CSRRXX instrs

 		Bit #(XLEN)  predicted_pc;
		Epoch        epoch;

		Bit #(64)    inum;            // for debugging only
} RR_to_Retire
deriving (Bits, FShow);

// ================================================================
// Register Read => EX_Control => Retire

// ---------------- Register Read => EX_Control (BR/JAL/JALR)

typedef struct {Bit #(XLEN)  pc;
		Bit #(XLEN)  fallthru_pc;
		Bit #(32)    instr;
		Bit #(XLEN)  rs1_val;
		Bit #(XLEN)  rs2_val;
		Bit #(XLEN)  imm;
		Bit #(64)    inum;    // for debugging only
} RR_to_EX_Control
deriving (Bits, FShow);

// ---------------- EX_Control => Retire

typedef struct {Bool         exception;  // Misaligned BRANCH/JAL/JALR target
		Bit #(4)     cause;
		Bit #(XLEN)  tval;

		Bit #(XLEN)  next_pc;
		Bit #(XLEN)  data;          // Return-PC for JAL/JALR

		// for debugging only
		Bit #(32)    instr;
		Bit #(64)    inum;
		Bit #(XLEN)  pc;
} EX_Control_to_Retire
deriving (Bits, FShow);

// ================================================================
// Register Read => Execute pipes (Int, IMUL, FALU, DMem, ...) => Retire

// ---------------- Register Read => EX

typedef struct {Bit #(32)    instr;
		Bit #(XLEN)  rs1_val;
		Bit #(XLEN)  rs2_val;
		Bit #(XLEN)  imm;

		// for debugging only
		Bit #(64)    inum;
		Bit #(XLEN)  pc;
} RR_to_EX
deriving (Bits, FShow);

// ---------------- EX => Retire

typedef struct {Bool         exception;
		Bit #(4)     cause;
		Bit #(XLEN)  tval;

		Bit #(XLEN)  data;

		// for debugging only
		Bit #(64)    inum;
		Bit #(XLEN)  pc;
		Bit #(32)    instr;
} EX_to_Retire
deriving (Bits, FShow);

// ================================================================
// Retire => DMem commit/discard (store-buffer)

typedef struct {Bit #(64) inum;
		Bool      commit;    // True:commit, False:discard
} Retire_to_DMem_Commit
deriving (Bits, FShow);

// ****************************************************************
// Pipeline backward flows

// ---------------- Fetch <= Retire (redirect)

typedef struct {Bit #(64)   inum;     // for debugging only
		Bit #(XLEN) pc;       // for debugging only
		Bit #(32)   instr;    // for debugging only

		Bit #(XLEN) next_pc;
		Epoch       next_epoch;
} Fetch_from_Retire
deriving (Bits, FShow);

// ---------------- Register Write <= Retire (writeback)

typedef struct {Bit #(64)   inum;    // for debugging only
		Bit #(XLEN) pc;      // For debugging only
		Bit #(32)   instr;   // for debugging only
		Bit #(5)    rd;
		Bool        commit;    // True: write rd and release scoreboard reservation
		                       // False: just release scoreboard reservation
		Bit #(XLEN) data;
} RW_from_Retire
deriving (Bits, FShow);

// ****************************************************************
// ****************************************************************
// ****************************************************************
// Specialized fshow functions

function Fmt fshow_Fetch_to_Decode (Fetch_to_Decode x);
   Fmt f = $format ("    Fetch_to_Decode{");
   f = f + $format ("I_%0d", x.inum);
   f = f + $format (" pc:%08h", x.pc);
   f = f + $format (" pred:%08h epoch:%0d", x.predicted_pc, x.epoch);
   f = f + $format ("}");
   return f;
endfunction

function Fmt fshow_Decode_to_RR (Decode_to_RR x);
   Fmt f = $format ("    Decode_to_RR{");
   f = f + $format ("I_%0d", x.inum);
   f = f + $format (" pc:%08h", x.pc);
   f = f + $format (" instr:%08h", x.instr);
   f = f + $format (" pred:%08h epoch:%0d\n", x.predicted_pc, x.epoch);
   f = f + $format ("            ");
   f = f + $format ("fallthru:%08h ", x.fallthru_pc);
   if (x.exception) begin
      f = f + fshow_cause (x.cause);
      f = f + $format (" tval:%0h", x.tval);
   end
   else begin
      f = f + fshow (x.opclass);
      f = f + $format (" has_{rs1,rs2,rd}:{%0d,%0d,%0d} writes_mem:%0d, imm:%0h",
		       x.has_rs1, x.has_rs2, x.has_rd, x.writes_mem, x.imm);
   end
   f = f + $format ("}");
   return f;
endfunction

function Fmt fshow_RR_to_Retire (RR_to_Retire x);
   Fmt f = $format ("    RR_to_Retire{");
   f = f + $format ("I_%0d", x.inum);
   f = f + $format (" pc:%08h", x.pc);
   f = f + $format (" instr:%08h ", x.instr, fshow (x.exec_tag), "\n");
   f = f + $format ("                 ");
   f = f + $format ("pred:%08h epoch:%0d has_rd:%0d writes_mem:%0d\n",
		    x.predicted_pc, x.epoch, x.has_rd, x.writes_mem);
   f = f + $format ("                 ");
   f = f + $format ("fallthru:%08h", x.fallthru_pc);
   if (x.exception) begin
      f = f + $format (" ", fshow_cause (x.cause));
      f = f + $format (" tval:%0h", x.tval);
   end
   f = f + $format ("}");
   return f;
endfunction

function Fmt fshow_RR_to_EX_Control (RR_to_EX_Control x);
   Fmt f = $format ("    RR_to_EX_Control{");
   f = f + $format ("I_%0d", x.inum);
   f = f + $format (" pc:%08h", x.pc);
   f = f + $format (" instr:%08h", x.instr);
   f = f + $format (" fallthru:%08h\n", x.fallthru_pc);
   f = f + $format ("                  ");
   f = f + $format ("rs1_val:%08h ", x.rs1_val);
   f = f + $format (" rs2_val:%08h ", x.rs2_val);
   f = f + $format (" imm:%08h ", x.imm);
   f = f + $format ("}");
   return f;
endfunction

function Fmt fshow_EX_Control_to_Retire (EX_Control_to_Retire x);
   Fmt f = $format ("    EX_Control_to_Retire{");
   f = f + $format ("I_%0d", x.inum);
   f = f + $format (" pc:%08h", x.pc);
   f = f + $format (" instr:%08h\n", x.instr);
   f = f + $format ("                      ");
   if (x.exception) begin
      f = f + $format (" ", fshow_cause (x.cause));
      f = f + $format (" tval:%0h", x.tval);
   end
   f = f + $format (" next_pc:%08h ", x.next_pc);
   f = f + $format (" data:%08h", x.data);
   f = f + $format ("}");
   return f;
endfunction

function Fmt fshow_RR_to_EX (RR_to_EX x);
   Fmt f = $format ("    RR_to_EX{");
   f = f + $format ("I_%0d", x.inum);
   f = f + $format (" pc:%08h", x.pc);
   f = f + $format (" instr:%08h\n", x.instr);
   f = f + $format ("             ");
   f = f + $format ("rs1_val:%08h ", x.rs1_val);
   f = f + $format (" rs2_val:%08h ", x.rs2_val);
   f = f + $format (" imm:%08h ", x.imm);
   f = f + $format ("}");
   return f;
endfunction

function Fmt fshow_EX_to_Retire (EX_to_Retire x);
   Fmt f = $format ("    EX_to_Retire{");
   f = f + $format ("I_%0d", x.inum);
   f = f + $format (" pc:%08h", x.pc);
   f = f + $format (" instr:%08h\n", x.instr);
   f = f + $format ("                 ");
   if (x.exception) begin
      f = f + $format (" ", fshow_cause (x.cause));
      f = f + $format (" tval:%0h", x.tval);
   end
   f = f + $format (" data:%08h", x.data);
   f = f + $format ("}");
   return f;
endfunction

function Fmt fshow_Fetch_from_Retire (Fetch_from_Retire x);
   Fmt f = $format ("    Fetch_from_Retire{");
   f = f + $format ("I_%0d", x.inum);
   f = f + $format (" pc:%08h", x.pc);
   f = f + $format (" instr:%08h", x.instr);
   f = f + $format (" next_pc:%08h next_epoch %0d", x.next_pc, x.next_epoch);
   f = f + $format ("}");
   return f;
endfunction

function Fmt fshow_RW_from_Retire (RW_from_Retire x);
   Fmt f = $format ("    RW_from_Retire{");
   f = f + $format ("I_%0d pc:%08h instr:%08h", x.inum, x.pc, x.instr);
   f = f + $format (" rd:%0d commit:%0d data:%08x", x.rd, x.commit, x.data);
   f = f + $format ("}");
   return f;
endfunction

// ****************************************************************

endpackage
