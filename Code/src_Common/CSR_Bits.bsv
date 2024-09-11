// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

package CSR_Bits;

// ****************************************************************
// Encodings used in CSRs

// ****************************************************************
// Imports from libraries

// None

// ----------------
// Local imports

import Arch       :: *;
import Instr_Bits :: *;    // For XLEN, xlen

// ****************************************************************
// Privilege levels

Bit #(2) priv_M = 2'b_11;
Bit #(2) priv_S = 2'b_01;
Bit #(2) priv_U = 2'b_00;

Bit #(2) priv_Reserved = 2'b_10;

// ****************************************************************
// CSR addresses

Bit #(12) csr_addr_MTVEC     = 'h305;
Bit #(12) csr_addr_MEPC      = 'h341;
Bit #(12) csr_addr_MCAUSE    = 'h342;
Bit #(12) csr_addr_MTVAL     = 'h343;

Bit #(12) csr_addr_CYCLE     = 'hC00;
Bit #(12) csr_addr_TIME      = 'hC01;
Bit #(12) csr_addr_INSTRET   = 'hC02;

Bit #(12) csr_addr_CYCLEH    = 'hC80;
Bit #(12) csr_addr_TIMEH     = 'hC81;
Bit #(12) csr_addr_INSTRETH  = 'hC82;

Bit #(12) csr_addr_MVENDORID = 'hF11;
Bit #(12) csr_addr_MARCHID   = 'hF12;
Bit #(12) csr_addr_MIMPID    = 'hF13;
Bit #(12) csr_addr_MHARTID   = 'hF14;

Bit #(12) csr_addr_MSTATUS   = 'h300;
Bit #(12) csr_addr_MISA      = 'h301;
Bit #(12) csr_addr_MIE       = 'h304;
Bit #(12) csr_addr_MSTATUSH  = 'h310;

Bit #(12) csr_addr_MSCRATCH  = 'h340;
Bit #(12) csr_addr_MIP       = 'h344;

Bit #(12) csr_addr_MCYCLE    = 'hB00;
//                 MTIME is an MMIO location, not a CSR
Bit #(12) csr_addr_MINSTRET  = 'hB02;

Bit #(12) csr_addr_MCYCLEH   = 'hB80;
//                 MTIMEH is an MMIO location, not a CSR
Bit #(12) csr_addr_MINSTRETH = 'hB82;

// Debugger support
Bit #(12) csr_addr_DCSR      = 'h7B0;
Bit #(12) csr_addr_DPC       = 'h7B1;

// ****************************************************************
// MSTATUS fields

Integer bitpos_MSTATUS_MIE  = 3;
Integer bitpos_MSTATUS_MPIE = 7;
Integer bitpos_MSTATUS_MPP  = 11;
Integer bitpos_MSTATUS_MPRV = 17;

Bit #(XLEN) mask_MSTATUS_MIE  = truncate (64'h_1 << bitpos_MSTATUS_MIE);
Bit #(XLEN) mask_MSTATUS_MPIE = truncate (64'h_1 << bitpos_MSTATUS_MPIE);
Bit #(XLEN) mask_MSTATUS_MPP  = truncate (64'h_3 << bitpos_MSTATUS_MPP);
Bit #(XLEN) mask_MSTATUS_MPRV = truncate (64'h_1 << bitpos_MSTATUS_MPRV);

// ****************************************************************
// Exception causes

Bit #(XLEN) cause_interrupt_bit = (1 << (xlen-1));

// ----------------
// Synchronous (trap)

Bit #(4) cause_INSTRUCTION_ADDRESS_MISALIGNED = 0;
Bit #(4) cause_INSTRUCTION_ACCESS_FAULT       = 1;
Bit #(4) cause_ILLEGAL_INSTRUCTION            = 2;
Bit #(4) cause_BREAKPOINT                     = 3;

Bit #(4) cause_LOAD_ADDRESS_MISALIGNED        = 4;
Bit #(4) cause_LOAD_ACCESS_FAULT              = 5;
Bit #(4) cause_STORE_AMO_ADDRESS_MISALIGNED   = 6;
Bit #(4) cause_STORE_AMO_ACCESS_FAULT         = 7;

Bit #(4) cause_ECALL_FROM_U                   = 8;
Bit #(4) cause_ECALL_FROM_S                   = 9;
// Reserved 10
Bit #(4) cause_ECALL_FROM_M                   = 11;

Bit #(4) cause_INSTRUCTION_PAGE_FAULT         = 12;
Bit #(4) cause_LOAD_PAGE_FAULT                = 13;
// Reserved 14
Bit #(4) cause_STORE_AMO_PAGE_FAULT           = 15;

// ----------------
// Asynchronous (interrupt)

// Reserved 0
Bit #(4) cause_SUPERVISOR_SOFTWARE_INTERRUPT  = 1;
// Reserved 1
Bit #(4) cause_MACHINE_SOFTWARE_INTERRUPT     = 3;
// Reserved 4
Bit #(4) cause_SUPERVISOR_TIMER_INTERRUPT     = 5;
// Reserved 6
Bit #(4) cause_MACHINE_TIMER_INTERRUPT        = 7;
// Reserved 8
Bit #(4) cause_SUPERVISOR_EXTERNAL_INTERRUPT  = 9;
// Reserved 10
Bit #(4) cause_MACHINE_EXTERNAL_INTERRUPT     = 11;

// ----------------

function Fmt fshow_cause (Bit #(4) cause);
   case (cause)
      cause_INSTRUCTION_ADDRESS_MISALIGNED: $format ("INSTR_ADDR_MISALIGNED");
      cause_INSTRUCTION_ACCESS_FAULT:       $format ("INSTR_ACCESS_FAULT");
      cause_ILLEGAL_INSTRUCTION:            $format ("ILLEGAL_INSTR");
      cause_BREAKPOINT:                     $format ("BREAKPOINT");

      cause_LOAD_ADDRESS_MISALIGNED:        $format ("LD_ADDR_MISALIGNED");
      cause_LOAD_ACCESS_FAULT:              $format ("LD_ACCESS_FAULT");
      cause_STORE_AMO_ADDRESS_MISALIGNED:   $format ("ST_AMO_ADDR_MISALIGNED");
      cause_STORE_AMO_ACCESS_FAULT:         $format ("ST_AMO_ACCESS_FAULT");

      cause_ECALL_FROM_U:                   $format ("ECALL_U");
      cause_ECALL_FROM_S:                   $format ("ECALL_S");
      cause_ECALL_FROM_M:                   $format ("ECALL_M");

      cause_INSTRUCTION_PAGE_FAULT:         $format ("INSTR_PAGE_FAULT");
      cause_LOAD_PAGE_FAULT:                $format ("LD_PAGE_FAULT");
      cause_STORE_AMO_PAGE_FAULT:           $format ("ST_AMO_PAGE_FAULT");
      default:                              $format ("<cause code %0d>", cause);
   endcase
endfunction

// ****************************************************************
// DCSR fields

Integer index_dcsr_ebreakm = 15;
Integer index_dcsr_ebreaku = 13;
Integer index_dcsr_cause   =  6;
Integer index_dcsr_step    =  2;
Integer index_dcsr_prv     =  0;

// DCSR cause field codes    (halt cause)

Bit #(3) dcsr_cause_ebreak       = 1;
Bit #(3) dcsr_cause_trigger      = 2;
Bit #(3) dcsr_cause_haltreq      = 3;
Bit #(3) dcsr_cause_step         = 4;
Bit #(3) dcsr_cause_resethaltreq = 5;
Bit #(3) dcsr_cause_group        = 6;
Bit #(3) dcsr_cause_other        = 7;

// ****************************************************************

endpackage
