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

function Bit #(XLEN) fn_legalize_mstatus (Bit #(XLEN) x);
   Bit #(XLEN) y = x;
   // Currently implementing only M mode
   if (x [bitpos_MSTATUS_MPP+1 : bitpos_MSTATUS_MPP] != priv_M)
      y = ((y & (~ mask_MSTATUS_MPP)) | (zeroExtend (priv_M) << bitpos_MSTATUS_MPP));
   return y;
endfunction

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

   // xRET actions
   // Returns PC from MEPC
   method ActionValue #(Bit #(XLEN)) mav_xRET ();

   method Bit #(XLEN) read_epc;
   method Action ma_incr_instret;

   // Set TIME
   (* always_ready, always_enabled *)
   method Action set_TIME (Bit #(64) t);

   // Debugger support
   method ActionValue #(Bool)
          csr_write (Bit #(12) csr_addr, Bit #(XLEN) csr_val);
   method ActionValue #(Tuple2 #(Bool, Bit #(XLEN)))
          csr_read (Bit #(12) csr_addr);
   method Action save_dpc_dcsr_cause_prv (Bit #(XLEN) pc, Bit #(3) cause, Bit #(2) prv);
   (* always_ready *)
   method Bit #(XLEN) get_dpc;
   (* always_ready *)
   method Bit #(32)   get_dcsr;
endinterface

// ****************************************************************

(* synthesize *)
module mkCSRs (CSRs_IFC);
   Reg #(File) rg_flog <- mkReg (InvalidFile);    // For debugging in simulation only

   Bit #(XLEN) one = 1;
   let misa_I   = (one << 8);
   let misa_mxl = (one << (xlen - 2));
   let misa     = (misa_mxl | misa_I);

   Reg #(Bit #(XLEN)) csr_mstatus  <- mkReg (fn_legalize_mstatus (0));
   Reg #(Bit #(XLEN)) csr_mie      <- mkReg (0);
   Reg #(Bit #(XLEN)) csr_mtvec    <- mkReg (0);
   Reg #(Bit #(XLEN)) csr_mscratch <- mkReg (0);
   Reg #(Bit #(XLEN)) csr_mepc     <- mkReg (0);
   Reg #(Bit #(XLEN)) csr_mcause   <- mkReg (0);
   Reg #(Bit #(XLEN)) csr_mtval    <- mkReg (0);

   Reg #(Bit #(32))   csr_dcsr     <- mkReg (0);
   Reg #(Bit #(XLEN)) csr_dpc      <- mkRegU;
   // No csr_dscratch0/csr_dscratch0 because not supporting DM Program Buffer

   Reg #(Bit #(64))   csr_minstret <- mkReg (0);

   // ================================================================
   // CSR MCYCLE (a) increments on its own, but (b) may also be written by CSRRxx
   // The spec says: (b) overrides (a).
   // We use a CReg for this: port 0 for (a), port 1 for (b).

   Array #(Reg #(Bit #(64))) csr_mcycle <- mkCReg (2, 0);

   (* fire_when_enabled, no_implicit_conditions *)    // Fire on every clock
   rule rl_count_cycles;
      csr_mcycle [0] <= csr_mcycle [0] + 1;
   endrule

   // ================================================================
   // CSR TIME is fed from outside, as a shadow of MMIO location MTIME.
   // Here we use a CReg: port 0 for external feed; port 1 for CSRRxx-read

   Array #(Reg #(Bit #(64))) crg_csr_TIME <- mkCReg (2, 0);

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
	    csr_addr_MISA:      noAction;    // read-only
	    csr_addr_MVENDORID: noAction;    // read-only
	    csr_addr_MARCHID:   noAction;    // read-only
	    csr_addr_MIMPID:    noAction;    // read-only
	    csr_addr_MHARTID:   noAction;    // read-only
	    csr_addr_MSTATUS:  csr_mstatus  <= fn_legalize_mstatus (csr_val);
	    csr_addr_MIE  :    csr_mie      <= csr_val;
	    csr_addr_MTVEC:    csr_mtvec    <= csr_val;
	    csr_addr_MSCRATCH: csr_mscratch <= csr_val;
	    csr_addr_MEPC:     csr_mepc     <= csr_val;
	    csr_addr_MCAUSE:   csr_mcause   <= csr_val;
	    csr_addr_MTVAL:    csr_mtval    <= csr_val;

	    csr_addr_MCYCLE:    if (xlen == 32)
				   csr_mcycle [1] <= {csr_mcycle [1] [63:32],
						      csr_val [31:0]  };
				else
				   csr_mcycle [1] <= zeroExtend (csr_val);
	    csr_addr_MCYCLEH:   if (xlen == 32)
				   csr_mcycle [1] <= {csr_val [31:0],
						      csr_mcycle [1] [31:0] };
			        else
				   exception = True;

	    csr_addr_MINSTRET:  if (xlen == 32)
				   csr_minstret <= {csr_minstret [63:32], csr_val [31:0]};
				else
				   csr_minstret <= zeroExtend (csr_val);
	    csr_addr_MINSTRETH: if (xlen == 32)
				   csr_minstret <= {csr_val [31:0], csr_minstret [31:0]};
				else
				   exception = True;
	    // Debugger control
	    csr_addr_DCSR:     csr_dcsr     <= truncate (csr_val);
	    csr_addr_DPC:      csr_dpc      <= csr_val;

	    default:            exception = True;
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
	    csr_addr_MISA:      y = misa;
	    csr_addr_MVENDORID: y = 0;
	    csr_addr_MARCHID:   y = 0;
	    csr_addr_MIMPID:    y = 0;
	    csr_addr_MHARTID:   y = 0;
	    csr_addr_MSTATUS:   y = csr_mstatus;
	    csr_addr_MIE:       y = csr_mie;
	    csr_addr_MTVEC:     y = csr_mtvec;
	    csr_addr_MSCRATCH:  y = csr_mscratch;
	    csr_addr_MEPC:      y = csr_mepc;
	    csr_addr_MCAUSE:    y = csr_mcause;
	    csr_addr_MTVAL:     y = csr_mtval;

	    csr_addr_CYCLE:     y = truncate (csr_mcycle [1]);
	    csr_addr_CYCLEH:    if (xlen == 32)
				   y = csr_mcycle [1] [63:32];
				else
				   exception = True;

	    csr_addr_MCYCLE:    y = truncate (csr_mcycle [1]);
	    csr_addr_MCYCLEH:   if (xlen == 32)
				   y = csr_mcycle [1] [63:32];
				else
				   exception = True;

	    csr_addr_TIME:      y = truncate (crg_csr_TIME [1]);
	    csr_addr_TIMEH:     if (xlen == 32)
				   y = crg_csr_TIME [1] [63:32];
				else
				   exception = True;

	    csr_addr_MINSTRET:    y = truncate (csr_minstret);
	    csr_addr_MINSTRETH: if (xlen == 32)
				   y = csr_minstret [63:32];
				else
				   exception = True;
	    csr_addr_INSTRET:   y = truncate (csr_minstret);
	    csr_addr_INSTRETH:  if (xlen == 32)
				   y = csr_minstret [63:32];
				else
				   exception = True;
	    // Debugger control
	    csr_addr_DCSR:     y = zeroExtend (csr_dcsr);
	    csr_addr_DPC:      y = csr_dpc;

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
   // CSRRXX method actions
   // Increments minstret if not exception, and if CSRRXX does not write minstret
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
	 if (is_CSRRxI (instr)) rs1_val = zeroExtend (rs1);

	 // Results
	 Bool        exception     = False;
	 Bit #(XLEN) rd_val        = ?;
	 Bool        wrote_instret = False;

	 if (is_CSRRWx (instr)) begin
	    // CSRRW and CSRRWI
	    if (rd != 0) begin
	       match { .exc, .v } <- fav_csr_read (csr_addr);
	       exception = exc;
	       rd_val    = v;
	    end
	    if (! exception) begin
	       let exc <- fav_csr_write (csr_addr, rs1_val);
	       wrote_instret = ((! exc)
				&& ((csr_addr == csr_addr_MINSTRET)
				    || (csr_addr == csr_addr_MINSTRETH)));
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
	       wrote_instret = ((! exc1)
				&& ((csr_addr == csr_addr_MINSTRET)
				    || (csr_addr == csr_addr_MINSTRETH)));
	       exception = exc1;
	    end
	 end
	 if (! wrote_instret)
	    csr_minstret <= csr_minstret + 1;

	 return tuple2 (exception, rd_val);
      endactionvalue
   endfunction

   // ================================================================
   // Exception method actions

   // When a trap is taken from privilege mode y into privilege mode
   // x, xPIE is set to the value of xIE; xIE is set to 0; and xPP is
   // set to y.

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

	 // Push interrupt and privilege stack
	 //   Clear MIE and MPIE
	 Bit #(XLEN) new_mstatus = (csr_mstatus
				    & (~ mask_MSTATUS_MIE)
				    & (~ mask_MSTATUS_MPIE));
	 //   Set MPIE to old MIE
	 if (csr_mstatus [bitpos_MSTATUS_MIE] == 1'b1)
	    new_mstatus = new_mstatus | mask_MSTATUS_MPIE;

	 // Compute trap PC to be returned
	 Bit #(XLEN) base        = (csr_mtvec & (~ 'h3));    // mask out [1:0]
	 Bool        is_vectored = (csr_mtvec [1:0] == 2'b01);
	 Bit #(XLEN) trap_pc = ((is_vectored && is_interrupt)
				? base + (zeroExtend (cause) << 2)
				: base);

	 csr_mstatus <= new_mstatus;
	 wr_log (rg_flog, $format ("CSRs: fav_exception mstatus %08h => %08h",
				   csr_mstatus, new_mstatus));
	 return trap_pc;
      endactionvalue
   endfunction

   // ================================================================
   // xRET
   // Actions on MSTATUS:
   //   xIE is set to xPIE; xPIE is set to 1;
   //   the privilege mode is changed to y (value in MPP);
   //   xPP is set to the least-privileged supported mode (U if supported else M);
   //   If xPP̸ != M, also set MPRV=0.
   // Returns PC from MEPC

   function ActionValue #(Bit #(XLEN)) fav_xRET ();
      actionvalue
	 // Pop priv and interrupt stack
	 //   Clear MIE and set MPIE
	 Bit #(XLEN) new_mstatus = (csr_mstatus & (~ mask_MSTATUS_MIE)) | mask_MSTATUS_MPIE;
	 //   Set MIE to old MPIE
	 if (csr_mstatus [bitpos_MSTATUS_MPIE] == 1'b1)
	    new_mstatus = new_mstatus | mask_MSTATUS_MIE;

	 // The privilege mode is changed to y (value in MPP);
	 // -- No-op (only M-mode implemented)

	 //   xPP is set to the least-privileged supported mode (U if supported else M);
	 // -- No-op (only M-mode implemented)

         //   If (new) xPP̸ != M, also set MPRV=0.
         // -- No-op (only M-mode implemented)

	 csr_mstatus <= new_mstatus;
	 wr_log (rg_flog, $format ("CSRs: fav_xRET mstatus %08h => %08h",
				   csr_mstatus, new_mstatus));
	 return csr_mepc;
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

   // xRET actions
   method mav_xRET = fav_xRET;

   method Bit #(XLEN) read_epc = csr_mepc;

   method Action ma_incr_instret;
      csr_minstret <= csr_minstret + 1;
   endmethod

   // Set TIME
   method Action set_TIME (Bit #(64) t);
      crg_csr_TIME [0] <= t;
   endmethod

   // Debugger support
   method csr_write (csr_addr, csr_val) = fav_csr_write (csr_addr, csr_val);
   method csr_read  (csr_addr)          = fav_csr_read (csr_addr);

   method Action save_dpc_dcsr_cause_prv (Bit #(XLEN) pc, Bit #(3) cause, Bit #(2) prv);
      csr_dpc  <= pc;

      Bit #(XLEN) mask_cause_prv = 'b_1_1100_0011;
      Bit #(XLEN) new_cause_prv  = { 0, cause, 4'h0, prv };
      csr_dcsr <= ((csr_dcsr & (~ mask_cause_prv)) | new_cause_prv);
   endmethod

   method Bit #(32) get_dpc  = csr_dpc;
   method Bit #(32) get_dcsr = csr_dcsr;
endmodule

// ****************************************************************

endpackage
