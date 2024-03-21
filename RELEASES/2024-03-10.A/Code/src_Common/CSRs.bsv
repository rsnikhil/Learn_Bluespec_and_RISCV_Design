// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package CSRs;

// ****************************************************************
// The CSR register file

// ****************************************************************
// Imports from libraries

// None

// ----------------
// Imports from 'vendor' libs

import Cur_Cycle  :: *;

// ----------------
// Local imports

import Utils      :: *;
import Arch       :: *;
import Instr_Bits :: *;    // For XLEN, xlen
import CSR_Bits   :: *;

// ****************************************************************

interface CSRs_IFC;
   method Action init (Initial_Params initial_params);

   // CSRRXX instruction execution
   // Returns (True, ?) if exception else (False, rd_val)
   method ActionValue #(Tuple2 #(Bool, Bit #(XLEN)))
          mav_csrrxx (Bit #(32) instr, Bit #(XLEN) rs1_val);

   // Trap actions
   // Returns PC from MTVEC for trap handler
   method ActionValue #(Bit #(XLEN))
          mav_exception (Bit #(XLEN) epc,
			 Bool        is_interrupt,
			 Bit #(4)    cause,
			 Bit #(XLEN) tval);

   method Bit #(XLEN) read_epc;
endinterface

// ****************************************************************

(* synthesize *)
module mkCSRs (CSRs_IFC);
   Reg #(File) rg_flog <- mkReg (InvalidFile);    // For debugging in simulation only

   Reg #(Bit #(XLEN)) csr_mstatus <- mkReg (0);
   Reg #(Bit #(XLEN)) csr_mie     <- mkReg (0);
   Reg #(Bit #(XLEN)) csr_mtvec   <- mkReg (0);
   Reg #(Bit #(XLEN)) csr_mepc    <- mkReg (0);
   Reg #(Bit #(XLEN)) csr_mcause  <- mkReg (0);
   Reg #(Bit #(XLEN)) csr_mtval   <- mkReg (0);

   // ================================================================
   // CSR write based on CSR addr
   // Returns True (exception) or False (ok)

   function ActionValue #(Bool)
            fav_csr_write (Bit #(12) csr_addr, Bit #(XLEN) csr_val);
      actionvalue
	 wr_log (rg_flog, $format ("CSRs: Writing csr_addr %03h <= %08h",
				   csr_addr, csr_val));

	 Bool exception = False;
	 case (csr_addr)
	    csr_addr_MSTATUS: csr_mstatus <= csr_val;
	    csr_addr_MIE  :   csr_mie     <= csr_val;
	    csr_addr_MTVEC:   csr_mtvec   <= csr_val;
	    csr_addr_MEPC:    csr_mepc    <= csr_val;
	    csr_addr_MCAUSE:  csr_mcause  <= csr_val;
	    csr_addr_MTVAL:   csr_mtval   <= csr_val;
	    default:          exception = True;
	 endcase
	 return exception;
      endactionvalue
   endfunction

   // ================================================================
   // CSR read based on CSR addr
   // Returns True (exception, ?) or False (ok, csr_val)


   function ActionValue #(Tuple2 #(Bool, Bit #(XLEN)))
            fav_csr_read (Bit #(12) csr_addr);
      actionvalue
	 wr_log (rg_flog, $format ("CSRs: Reading csr_addr %03h",
				   csr_addr));
	 Bool        exception = False;
	 Bit #(XLEN) y         = ?;
	 case (csr_addr)
	    csr_addr_MVENDORID: y = 0;
	    csr_addr_MARCHID:   y = 0;
	    csr_addr_MIMPID:    y = 0;
	    csr_addr_MHARTID:   y = 0;
	    csr_addr_MSTATUS:   y = csr_mstatus;
	    csr_addr_MIE:       y = csr_mie;
	    csr_addr_MTVEC:     y = csr_mtvec;
	    csr_addr_MEPC:      y = csr_mepc;
	    csr_addr_MCAUSE:    y = csr_mcause;
	    csr_addr_MTVAL:     y = csr_mtval;
	    default:            exception = True;
	 endcase

	 if (exception)
	    wr_log_cont (rg_flog, $format ("    => exception"));
	 else
	    wr_log_cont (rg_flog, $format ("    => rd_val:%08h", y));

	 return tuple2 (exception, y);
      endactionvalue
   endfunction

   // ================================================================
   // CSRRXX actions
   // Returns (True, ?) if exception else (False, rd_val)

   function ActionValue #(Tuple2 #(Bool, Bit #(XLEN)))
            fav_csrrxx (Bit #(32) instr, Bit #(XLEN) rs1_val);
      actionvalue
	 wr_log (rg_flog, $format ("CSRs: csrrxx instr %08h rs1_val %08h",
				   instr, rs1_val));

	 Bit #(12) csr_addr = instr_imm_I (instr);
	 Bit #(5)  rs1      = instr_rs1 (instr);
	 Bit #(5)  rd       = instr_rd (instr);

	 // rs1_val is from register. Replace with immed if necessary.
	 if (is_CSRRxI (instr)) rs1_val = signExtend (rs1);

	 // Results
	 Bool        exception = False;
	 Bit #(XLEN) rd_val    = ?;

	 if (is_CSRRWx (instr)) begin
	    // CSRRW and CSRRWI
	    if (rd != 0) begin
	       match { .exc, .v } <- fav_csr_read (csr_addr);
	       exception = exc;
	       rd_val    = v;
	    end
	    if (! exception) begin
	       let exc <- fav_csr_write (csr_addr, rs1_val);
	       exception = exc;
	    end
	 end
	 else begin
	    // CSRRS, CSRRC, CSRRSI, CSRRCI
	    match { .exc, .v_old } <- fav_csr_read (csr_addr);
	    exception = exc;
	    rd_val    = v_old;
	    if ((! exception) && (rs1 != 0)) begin
	       let v_new = (is_CSRRSx (instr)
			    ? (v_old | rs1_val)
			    : (v_old & (~ rs1_val)));
	       let exc1 <- fav_csr_write (csr_addr, v_new);
	       exception = exc1;
	    end
	 end
	 return tuple2 (exception, rd_val);
      endactionvalue
   endfunction

   // ================================================================
   // Trap actions
   // Returns PC from MTVEC for trap handler

   function ActionValue #(Bit #(XLEN))
            fav_exception (Bit #(XLEN) epc,
			   Bool        is_interrupt,
			   Bit #(4)    cause,
			   Bit #(XLEN) tval);
      actionvalue
	 // Save values
	 csr_mepc   <= epc;
	 Bit #(XLEN) mcause_msb = (is_interrupt ? (1 << (xlen-1)) : 0 );
	 csr_mcause <= (mcause_msb | zeroExtend (cause));
	 csr_mtval  <= tval;

	 // Compute and return trap PC
	 Bit #(XLEN) base        = (csr_mtvec & (~ 'h3));    // mask out [1:0]
	 Bool        is_vectored = (csr_mtvec [1:0] == 2'b01);
	 Bit #(XLEN) trap_pc = ((is_vectored && is_interrupt)
				? base + (zeroExtend (cause) << 2)
				: base);
	 return trap_pc;
      endactionvalue
   endfunction

   // ================================================================
   // INTERFACE

   method Action init (Initial_Params initial_params);
      rg_flog <= initial_params.flog;
   endmethod

   // CSRRXX instruction execution
   method mav_csrrxx = fav_csrrxx;

   // Trap actions
   method mav_exception = fav_exception;

   method Bit #(XLEN) read_epc = csr_mepc;
endmodule

// ****************************************************************

endpackage
