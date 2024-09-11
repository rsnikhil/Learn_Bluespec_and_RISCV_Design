// ================================================================
// Copyright (c) 2024 Rishiyur S. Nikhil. All Rights Reserved

// EDB: "Economical/Elementary Debugger"

// ****************************************************************
// Includes from C library

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>

// ----------------
// Includes for this project

#include "Dbg_Pkts.h"

// ****************************************************************
// Help functions to print packets

void print_to_CPU_pkt (FILE *fd,
		       const char *pre,
		       const Dbg_to_CPU_Pkt *p_pkt,
		       const char *post)
{
    fprintf (fd, "%s", pre);

    switch (p_pkt->pkt_type) {
    case Dbg_to_CPU_RESUMEREQ: fprintf (fd, " RESUMEREQ"); break;
    case Dbg_to_CPU_HALTREQ:   fprintf (fd, " HALTREQ");   break;
    case Dbg_to_CPU_RW: {
	switch (p_pkt->rw_op) {
	case Dbg_RW_READ:  fprintf (fd, " READ");  break;
	case Dbg_RW_WRITE: fprintf (fd, " WRITE"); break;
	default: fprintf (fd, "  <UNKNOWN Dbg_RW_Op %0d?>", p_pkt->rw_op); break;
	}
	switch (p_pkt->rw_size) {
	case Dbg_MEM_1B: fprintf (fd, " 1B ");  break;
	case Dbg_MEM_2B: fprintf (fd, " 2B"); break;
	case Dbg_MEM_4B: fprintf (fd, " 4B"); break;
	case Dbg_MEM_8B: fprintf (fd, " 8B"); break;
	default: fprintf (fd, " <UNKNOWN Dbg_RW_Size %0d?>", p_pkt->rw_size); break;
	}
	switch (p_pkt->rw_target) {
	case Dbg_RW_GPR:  fprintf (fd, "  GPR x%0" PRId64,  p_pkt->rw_addr);  break;
	case Dbg_RW_FPR:  fprintf (fd, "  FPR f%0" PRId64,  p_pkt->rw_addr); break;
	case Dbg_RW_CSR:  fprintf (fd, "  CSR 0x%0" PRIx64, p_pkt->rw_addr); break;
	case Dbg_RW_MEM:  fprintf (fd, "  Mem 0x%0" PRIx64, p_pkt->rw_addr); break;
	default: fprintf (fd, " <UNKNOWN Dbg_RW_Target %0d?>", p_pkt->rw_target); break;
	}
	if (p_pkt->rw_op == Dbg_RW_WRITE) fprintf (fd, " 0x%0" PRIx64, p_pkt->rw_wdata);
	fprintf (fd, "");
	break;
    }
    case Dbg_to_CPU_QUIT: fprintf (fd, " QUIT");   break;
    default: fprintf (fd, " <unknown Dbg_to_CPU_Pkt_Type %0d>", p_pkt->pkt_type);
    }

    fprintf (fd, "%s", post);
}

// ================================================================

void print_from_CPU_pkt (FILE *fd,
			 const char *pre,
			 const Dbg_from_CPU_Pkt *p_pkt,
			 const char *post)
{
    fprintf (fd, "%s", pre);

    switch (p_pkt->pkt_type) {
    case Dbg_from_CPU_RESUMEACK: fprintf (fd, " RESUMEACK"); break;
    case Dbg_from_CPU_RUNNING:   fprintf (fd, " RUNNING");   break;
    case Dbg_from_CPU_RW_OK:     fprintf (fd, " RW_OK");     break;
    case Dbg_from_CPU_HALTED:
	fprintf (fd, " HALTED; cause ");
	switch (p_pkt->payload) {
	case dcsr_cause_EBREAK:  fprintf (fd, "EBREAK");  break;
	case dcsr_cause_STEP:    fprintf (fd, "STEP");    break;
	case dcsr_cause_HALTREQ: fprintf (fd, "HALTREQ"); break;
	default:                 fprintf (fd, "%" PRId64, p_pkt->payload);
	}
	break;
    case Dbg_from_CPU_ERR: fprintf (fd, " ERR %0" PRId64 "", p_pkt->payload); break;
    default: fprintf (fd, " <unknown Dbg_from_CPU_Pkt_Type %0d?>", p_pkt->pkt_type);
    }
    fprintf (fd, "%s", post);
}

// ****************************************************************
