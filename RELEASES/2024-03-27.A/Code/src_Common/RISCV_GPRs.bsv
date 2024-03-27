// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package RISCV_GPRs;

// ****************************************************************
// This is a 2-read-port register file of 32 registers.
// Register 0 ('x0') always reads as 0.
// Polymorphic: register-width ix 'xlen' (instantiated with 32 for RV32, 64 for RV64)

// ****************************************************************
// Imports from libraries

import RegFile :: *;
import Vector  :: *;

// ----------------
// Local imports

import Arch :: *;

// ****************************************************************
// Interface for GPRs

interface RISCV_GPRs_IFC #(numeric type xlen);
   method Bit #(xlen) read_rs1 (Bit #(5) rs1);
   method Bit #(xlen) read_rs2 (Bit #(5) rs2);
   method Action      write_rd (Bit #(5) rd, Bit #(xlen) rd_val);
endinterface

// ================================================================
// Two implementations of a GPR module

// ----------------------------------------------------------------
// GPRs module; first version
// BSV schedule: register-reads happen "before" register-write
// i.e., in case of concurrent (same-clock) read and write to same index,
// the "read" reads the old value and the "write" writes a new value
// that is available on the subsequent clock.

module mkRISCV_GPRs (RISCV_GPRs_IFC #(xlen));
   RegFile #(Bit #(5), Bit #(xlen)) rf <- mkRegFileFull;

   method Bit #(xlen) read_rs1 (Bit #(5) rs1);
      return ((rs1 == 0) ? 0 : rf.sub (rs1));
   endmethod

   method Bit #(xlen) read_rs2 (Bit #(5) rs2);
      return ((rs2 == 0) ? 0 : rf.sub (rs2));
   endmethod

   method Action write_rd (Bit #(5) rd, Bit #(xlen) rd_val);
      rf.upd (rd, rd_val);
   endmethod
endmodule

// ----------------
// A monomorphic version synthesized into Verilog

(* synthesize *)
module mkRISCV_GPRs_synth (RISCV_GPRs_IFC #(XLEN));
   let ifc <- mkRISCV_GPRs;
   return ifc;
endmodule

// ----------------------------------------------------------------
// GPRs module; "faster" version using "bypassing"

// BSV schedule: register-reads happen "after" register-write
// i.e., in case of concurrent (same-clock) read and write to same index,
// the "write" writes a new value, and "bypasses" it to the "read" immediately.

module mkRISCV_GPRs_bypassed (RISCV_GPRs_IFC #(xlen));

   RegFile #(Bit #(5), Bit #(xlen)) regfile <- mkRegFileFull;

   // Communicate reg-write (rd, rd_val) to reads and rl_write
   Array #(Reg #(Tuple2 #(Bit #(5), Bit #(xlen)))) crg <- mkCReg (2, tuple2 (0, 0));

   // ----------------
   // BEHAVIOR

   rule rl_write;
      match { .rd, .rd_val } = crg [1];
      regfile.upd (rd, rd_val);
   endrule

   // ----------------
   // INTERFACE

   method Bit #(xlen) read_rs1  (Bit #(5) rs1);
      match { .rd, .rd_val } = crg [1];
      return ((rs1 == rd) ? rd_val : regfile.sub (rs1));
   endmethod

   method Bit #(xlen) read_rs2  (Bit #(5) rs2);
      match { .rd, .rd_val } = crg [1];
      return ((rs2 == rd) ? rd_val : regfile.sub (rs2));
   endmethod

   method Action write_rd (Bit #(5) rd, Bit #(xlen) rd_val);
      let v = ((rd == 0) ? 0 : rd_val);
      crg [0] <= tuple2 (rd, rd_val);
   endmethod
endmodule

// ----------------
// A monomorphic version synthesized into Verilog

(* synthesize *)
module mkRISCV_GPRs_bypassed_synth (RISCV_GPRs_IFC #(XLEN));
   let ifc <- mkRISCV_GPRs_bypassed;
   return ifc;
endmodule

// ****************************************************************
// Interface for Scoreboard

// The scoreboard is a vector of 1-bit values indicating which of the
// 32 registers are "busy". scoreboard[X] is 1 when there is an older
// instruction in the downstream pipes that is expected to write into
// register X.

typedef  Vector #(32, Bit #(1))  Scoreboard;

interface Scoreboard_IFC;
   interface Reg #(Scoreboard) port0;
   interface Reg #(Scoreboard) port1;
endinterface

// ================================================================
// Two implementations of a scoreboard module

// ----------------------------------------------------------------
// Scoreboard module, first version

// Uses an ordinary register.
// Register-read (whether port0 or port1) schedule before
// register-write (whether port0 or port1).

module mkScoreboard (Scoreboard_IFC);
   Reg #(Scoreboard) rg <- mkReg (replicate (0));
   interface port0 = rg;
   interface port1 = rg;
endmodule

// ----------------------------------------------------------------
// Scoreboard module, "faster" version using "bypassing"

// This implementation uses a concurrent register
// Port0 write schedules before port1 read, bypassing the write-value to the read
module mkScoreboard_2 (Scoreboard_IFC);

   Array #(Reg #(Scoreboard))  crg_scoreboard <- mkCReg (2, replicate (0));

   interface port0 = crg_scoreboard [0];
   interface port1 = crg_scoreboard [1];
endmodule

// ****************************************************************

endpackage
