// ================================================================
// Copyright (c) 2024 Rishiyur S. Nikhil and Bluespec, Inc.  All Rights Reserved

// 'edb': Economical/Elementary Debugger

#pragma once

// ****************************************************************
// These are type definitions and help functions for packets exchanged
// between the debugger and the CPU

// ****************************************************************
// Debugber to CPU packets

typedef enum {Dbg_to_CPU_NOOP,
              Dbg_to_CPU_RESUMEREQ,
              Dbg_to_CPU_HALTREQ,
              Dbg_to_CPU_RW,
              Dbg_to_CPU_QUIT}     Dbg_to_CPU_Pkt_Type;

typedef enum {Dbg_RW_GPR, Dbg_RW_FPR, Dbg_RW_CSR, Dbg_RW_MEM} Dbg_RW_Target;
typedef enum {Dbg_RW_READ, Dbg_RW_WRITE}                      Dbg_RW_Op;
typedef enum {Dbg_MEM_1B, Dbg_MEM_2B, Dbg_MEM_4B, Dbg_MEM_8B} Dbg_RW_Size;

typedef struct {
    Dbg_to_CPU_Pkt_Type  pkt_type;
    // The remaining fields are only relevant for RW requests
    Dbg_RW_Target        rw_target;
    Dbg_RW_Op            rw_op;
    Dbg_RW_Size          rw_size;
    uint64_t             rw_addr;
    uint64_t             rw_wdata;
} Dbg_to_CPU_Pkt;

extern
void print_to_CPU_pkt (FILE                 *fd,
		       const char           *pre,
		       const Dbg_to_CPU_Pkt *p_pkt,
		       const char           *post);

// ****************************************************************
// Debugger from CPU packets

typedef enum {Dbg_from_CPU_RESUMEACK,
              Dbg_from_CPU_RUNNING,
              Dbg_from_CPU_HALTED,
              Dbg_from_CPU_RW_OK,
              Dbg_from_CPU_ERR}      Dbg_from_CPU_Pkt_Type;

typedef struct {
    Dbg_from_CPU_Pkt_Type  pkt_type;
    uint64_t               payload;  // halt-reason in HALTED responses
                                     // read-data   in RW_OK  resp for RW:RW_READ req
                                     // error-code  in ERR    responses
                                     // unused/don't care otherwise
} Dbg_from_CPU_Pkt;

extern
void print_from_CPU_pkt (FILE                   *fd,
			 const char             *pre,
			 const Dbg_from_CPU_Pkt *p_pkt,
			 const char             *post);

// ****************************************************************
// DCSR details (these are standard RISC-V definitions)

#define addr_csr_dcsr 0x7b0
#define addr_csr_dpc  0x7b1

#define mask_dcsr_step     (1 << 2)
#define mask_dcsr_ebreakvs (1 << 17)
#define mask_dcsr_ebreakvu (1 << 16)
#define mask_dcsr_ebreakm  (1 << 15)
#define mask_dcsr_ebreaks  (1 << 13)
#define mask_dcsr_ebreaku  (1 << 12)

#define mask_dcsr_cause  (0x7 << 6)

#define DCSR_CAUSE(dcsr) (((dcsr) >> 6) & 0x7)
#define dcsr_cause_EBREAK        1
#define dcsr_cause_TRIGGER       2
#define dcsr_cause_HALTREQ       3
#define dcsr_cause_STEP          4
#define dcsr_cause_RESETHALTREQ  5
#define dcsr_cause_GROUP         6
#define dcsr_cause_OTHER         7

// ****************************************************************
