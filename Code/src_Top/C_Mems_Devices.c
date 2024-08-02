// Copyright (c) 2023-2024 Bluespec, Inc.  All Rights Reserved.
// Author: Rishiyur S. Nikhil

// ****************************************************************
// Imported C functions for a memory-model

// Current:
//   Version 2 (without store-buffer, which has moved up into BSV)

// Historical:
//   Version 1 (with store-buffer)
//     commit 12beee5f000439504c1e46e63238329584ea5589
//     Date:   Thu Jul 25 12:09:53 2024 -0400
//     copy at: Git_Aux/Fife/ATTIC/2024-07-29_C_Mems_Devices.c)

// ****************************************************************
// Includes from C lib

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <ctype.h>
#include <inttypes.h>
#include <string.h>

// ----------------
// Local includes

#include "UART_model.h"

// ****************************************************************
// Debugging message control

static int verbosity_wild = 1;
static int verbosity_mem  = 0;
static int verbosity_MMIO = 0;

// ****************************************************************

#define minimum(x,y) (((x) <= (y)) ? (x) : (y))

// ****************************************************************
// WARNING: THESE CODES SHOULD BE IDENTICAL TO THOSE IN Mem_Req_Rsp.bsv

// For LOAD/STORE Mem_Req_Type codes we utilize two 5-bit codes
// that are not used by any AMO op
#define funct5_FENCE    0x1D    // 11101
#define funct5_LOAD     0x1E    // 11110
#define funct5_STORE    0x1F    // 11111

// ----------------
// For Mem_Req_Type codes we use the original funct5 codes for AMO ops
#define funct5_LR       0x02    // 00010
#define funct5_SC       0x03    // 00011
#define funct5_AMOSWAP  0x01    // 00001
#define funct5_AMOADD   0x00    // 00000
#define funct5_AMOXOR   0x04    // 00100
#define funct5_AMOAND   0x0C    // 01100
#define funct5_AMOOR    0x08    // 01000
#define funct5_AMOMIN   0x10    // 10000
#define funct5_AMOMAX   0x14    // 10100
#define funct5_AMOMINU  0x18    // 11000
#define funct5_AMOMAXU  0x1C    // 11100

// ----------------
// Memory request-size codes

#define MEM_1B 0
#define MEM_2B 1
#define MEM_4B 2
#define MEM_8B 3

// ----------------
// Memory response types

#define MEM_RSP_OK          0
#define MEM_RSP_MISALIGNED  1
#define MEM_RSP_ERR         2
#define MEM_REQ_DEFERRED    3

// ----------------
// Memory clients

#define CLIENT_IMEM  0
#define CLIENT_DMEM  1
#define CLIENT_MMIO  2

static
void fprintf_client (FILE *fp, const char *pre, const uint32_t client, const char *post)
{
    fprintf (fp, "%s", pre);
    switch (client) {
    case CLIENT_IMEM: fprintf (fp, "CLIENT_IMEM"); break;
    case CLIENT_DMEM: fprintf (fp, "CLIENT_DMEM"); break;
    case CLIENT_MMIO: fprintf (fp, "CLIENT_MMIO"); break;
    default:          fprintf (fp, "<client %0d>", client); break;
    }
    fprintf (fp, "%s", post);
}

// ****************************************************************
// System address map and components

// ----------------
// Memory

#define ADDR_BASE_MEM  0x80000000
#define SIZE_B_MEM     0x10000000

// #define ADDR_BASE_MEM  0x00000000
// #define SIZE_B_MEM     0x00010000

static uint8_t mem_array [SIZE_B_MEM];

// ----------------
// UART

#define ADDR_BASE_UART 0x60100000
#define SIZE_B_UART    0x00001000

static UART_16550 *uart_p = NULL;

// ----------------
// GPIO

#define ADDR_BASE_GPIO 0x6FFF0000
#define SIZE_B_GPIO    0x00010000

#define ADDR_OFFSET_GPIO_TOHOST 0x0010

static
uint32_t rg_tohost = 0;

// ================================================================
// Print-functions for debugging

static
void fprint_mems_devices_info (FILE *fp)
{
    fprintf (fp, "  Mem system model\n");

    fprintf (fp, "   ADDR_BASE_MEM:  0x%08x", ADDR_BASE_MEM);
    fprintf (fp, " SIZEB_MEM:  0x%08x (%0d) bytes\n", SIZE_B_MEM, SIZE_B_MEM);

    fprintf (fp, "   ADDR_BASE_UART: 0x%08x", ADDR_BASE_UART);
    fprintf (fp, " SIZEB_UART: 0x%08x (%0d) bytes\n", SIZE_B_UART, SIZE_B_UART);
}

// Print byte-array data, with special case as integer if <= 8 bytes
static
void fprint_data (FILE *fp,
		  const char     *pre,
		  const uint32_t  size_B,
		  const uint8_t  *data_p,
		  const char     *post)
{
    fprintf (fp, "%s", pre);
    if (size_B <= 8) {
	uint64_t data = 0;
	memcpy (& data, data_p, size_B);
	fprintf (stdout, "0x%08" PRIx64, data);
    }
    else {
	for (int j = 0; j < size_B; j++)
	    fprintf (stdout, "%02x", data_p [j]);
    }
    fprintf (fp, "%s", post);
}

static
void fprint_mem_req (FILE *fp,
		     const uint64_t   inum,
		     const uint32_t   req_type,
		     const uint32_t   size_B,
		     const uint64_t   addr,
		     const uint8_t   *wdata_p)
{
    fprintf (fp, "    Mem request I_%0" PRId64, inum);
    bool print_wdata = true;
    switch (req_type) {
    case funct5_FENCE:   fprintf (fp, " FENCE"); print_wdata = false; break;
    case funct5_LOAD:    fprintf (fp, " LOAD"); print_wdata = false; break;
    case funct5_STORE:   fprintf (fp, " STORE"); break;
    case funct5_LR:      fprintf (fp, " LR"); print_wdata = false; break;
    case funct5_SC:      fprintf (fp, " SC"); break;
    case funct5_AMOSWAP: fprintf (fp, " AMOSWAP"); break;
    case funct5_AMOADD:  fprintf (fp, " AMOADD");  break;
    case funct5_AMOXOR:  fprintf (fp, " AMOXOR");  break;
    case funct5_AMOAND:  fprintf (fp, " AMOAND");  break;
    case funct5_AMOOR:   fprintf (fp, " AMOOR");   break;
    case funct5_AMOMIN:  fprintf (fp, " AMOMIN");  break;
    case funct5_AMOMAX:  fprintf (fp, " AMOMAX");  break;
    case funct5_AMOMINU: fprintf (fp, " AMOMINU"); break;
    case funct5_AMOMAXU: fprintf (fp, " AMOMAXU"); break;
    default:             fprintf (fp, " (unknown req type 0x%0x)", req_type);
    }
    if (size_B != 0)
	fprintf (fp, " %0dB", size_B);
    fprintf (fp, " addr:%08" PRIx64, addr);
    if (print_wdata)
	fprint_data (fp, " wdata: ", size_B, wdata_p, "");
    fprintf (fp, "\n");
}

// ================================================================
// Load memhex32 file data into memory array

// Parse hex number allowing '_' and ' ' spacers
static
uint32_t parse_hex (const char *linebuf)
{
    int      j = 0;
    uint32_t x = 0;
    while (true) {
	uint8_t ch = linebuf [j];
	if      (('A' <= ch) && (ch <= 'F')) x = (x << 4) + (ch - 'A' + 10);
	else if (('a' <= ch) && (ch <= 'f')) x = (x << 4) + (ch - 'a' + 10);
	else if (('0' <= ch) && (ch <= '9')) x = (x << 4) + (ch - '0');
	else if ((ch == ' ') || (ch == '_')) { } // skip
	else                                 break;  // Done; ignore rest of line
	j++;
    }
    return x;
}

static
char default_memhex_filename[] = "test.memhex32";

static
void load_memhex32 (int verbosity)
{
    char *memhex_filename = getenv ("MEMHEX32");
    if (memhex_filename != NULL) {
	fprintf (stdout, "Loading memhex file %s\n", memhex_filename);
	fprintf (stdout, "    (from environment variable MEMHEX32)\n");
    }
    else {
	memhex_filename = default_memhex_filename;
	fprintf (stdout, "Loading memhex file %s\n", memhex_filename);
	fprintf (stdout, "    (default file---no env variable MEMHEX32)\n");
    }

    FILE *fp = fopen (memhex_filename, "r");
    if (fp == NULL) {
	fprintf (stdout, "Unable to open memhex file; ignoring; mem is not initialized\n");
	return;
    }

#define LINEBUF_SIZE 256
    char linebuf [LINEBUF_SIZE];
    
    int      line_num = 0;
    uint64_t addr = 0;

    while (true) {
	char *p = fgets (linebuf, LINEBUF_SIZE, fp);
	if (p == NULL) break;

	line_num++;
    
	if (linebuf [0] == '@') {
	    addr = (parse_hex (& (linebuf [1])) << 2);
	    if (verbosity > 0)
		fprintf (stdout, "  Setting addr = 0x%08" PRIx64 "\n", addr);
	}
	else if (isxdigit (linebuf [0])) {
	    uint32_t x = parse_hex (linebuf);
	    if ((addr - ADDR_BASE_MEM) > (SIZE_B_MEM - 4)) {
		fprintf (stdout,
			 "ERROR: load_memhex32(): addr 0x%08" PRIx64 " out of bounds\n", addr);
		fprintf (stdout,
			 "       Mem size is 0x%08x\n", SIZE_B_MEM);
		exit (1);
	    }
	    memcpy (& (mem_array [addr - ADDR_BASE_MEM]), & x, 4);
	    if (verbosity > 1)
		fprintf (stdout, "Loading mem [%08" PRIx64 "] <= %08x\n", addr, x);
	    addr += 4;
	}
	else {
	    // Ignore this line
	}
    }
}

// ================================================================
// Access memory
// (already checked that addr range is in-mem)

static
void c_access_mem (uint8_t        *result_p,
		   const uint64_t  inum,
		   const uint32_t  req_type,
		   const uint32_t  size_B,
		   const uint64_t  addr,
		   uint8_t        *wdata_p,
		   const int       verbosity)
{
    if (verbosity != 0)
	fprint_mem_req (stdout, inum, req_type, size_B, addr, wdata_p);

    uint32_t *status_p = (uint32_t *) result_p;
    *status_p = MEM_RSP_OK;

    uint8_t *mem_ptr = & (mem_array [addr - ADDR_BASE_MEM]);

    if (req_type == funct5_LOAD) {
	// rdata <= mem []
	uint8_t *rdata_p = & (result_p [4]);
	memcpy (rdata_p, mem_ptr, 8);

	if (verbosity != 0)
	    fprint_data (stdout, "    => rdata ", size_B, rdata_p, "\n");
    }
    else if (req_type == funct5_STORE) {
	// mem [] <= wdata
	memcpy (mem_ptr, wdata_p, size_B);

	if (verbosity != 0)
	    fprint_data (stdout, "    wdata_p <= ", size_B, wdata_p, "\n");
    }
    else {
	fprintf (stdout, "ERROR: %s: unknown request type", __FUNCTION__);
	fprint_mem_req (stdout, inum, req_type, size_B, addr, wdata_p);
	*status_p = MEM_RSP_ERR;
    }
}

// ================================================================
// Access UART

static
void c_access_UART (uint8_t        *result_p,
		    const uint64_t  inum,
		    const uint32_t  req_type,
		    const uint32_t  size_B,
		    const uint64_t  addr,
		    uint8_t        *wdata_p)
{
    uint32_t *status_p = (uint32_t *) result_p;
    if (req_type == funct5_LOAD) {
	fprintf (stdout, "ERROR: c_mem_access_UART(): LOAD not yet implemented\n");
	fprint_mem_req (stdout, inum, req_type, size_B, addr, wdata_p);
	*status_p = MEM_RSP_ERR;
    }
    else if (req_type == funct5_STORE) {
	uint8_t ch = *wdata_p;

	if (ch == '\r')      { fprintf (stdout, "\r"); fflush (stdout); }
	else if (ch == '\n') { fprintf (stdout, "\n"); fflush (stdout); }
	else if (ch <  0x20) fprintf (stdout, "UART: <0x%0x>\n", ch);
	else if (ch >= 0x7F) fprintf (stdout, "UART: <0x%0x>\n", ch);
	else                 fprintf (stdout, "%c", ch);
	*status_p = MEM_RSP_OK;
    }
    else {
	fprintf (stdout, "ERROR: %s: unknown request type", __FUNCTION__);
	fprint_mem_req (stdout, inum, req_type, size_B, addr, wdata_p);
	*status_p = MEM_RSP_ERR;
    }
}

// ****************************************************************
// ****************************************************************
// ****************************************************************
// Extern functions called from BSV

// ================================================================
// import "BDPI"
// function Action c_mems_devices_init (Bit #(32) dummy);

#ifdef __cplusplus
// 'C' linkage is necessary for linking with Verilator object files
extern "C" {
void c_mems_devices_init (uint32_t dummy);
}
#endif

// ----------------
// One-time initializations, including reading ELF and memhex into memory

void c_mems_devices_init (uint32_t dummy)
{
    fprintf (stdout, "INFO: %s\n", __FUNCTION__);
    fprint_mems_devices_info (stdout);

    // TODO: load multiple ELFs/memhex32s
    const int verbosity = 0;
    load_memhex32 (verbosity);

    // Instantiate UART model
    const uint8_t addr_stride = 4;
    uart_p = mkUART_16550 (ADDR_BASE_UART, addr_stride);
}

// ================================================================
// import "BDPI"
// function ActionValue #(Bit #(96)) c_mems_devices_req_rsp (Bit #(64)  inum,
//                                                           Bit #(32)  req_type,
//                                                           Bit #(32)  req_size,
//                                                           Bit #(64)  addr,
//                                                           Bit #(32)  client,
//                                                           Bit #(128) wdata);

#ifdef __cplusplus
// 'C' linkage is necessary for linking with Verilator object files
extern "C" {
void c_mems_devices_req_rsp (uint8_t        *result_p,
			     const uint64_t  inum,
			     const uint32_t  req_type,
			     const uint32_t  req_size_code,
			     const uint64_t  addr,
			     const uint32_t  client,
			     uint8_t        *wdata_p);
}
#endif

// ----------------
// wdata_p is a pointer to data to memory (for STORE, SC, AMOxxx)
// BSV result is a pointer in first arg of C function; points to:
//     32b (4 bytes) of status (OK, MISALIGNED, ERR)
//     followed by at least 64b (8 bytes) of data to CPU (for LOAD, LR, SC, AMOxxx)
// client is 0 for IMem, 1 for DMem, 2 for MMIO

void c_mems_devices_req_rsp (uint8_t        *result_p,
			     const uint64_t  inum,
			     const uint32_t  req_type,
			     const uint32_t  req_size_code,
			     const uint64_t  addr,
			     const uint32_t  client,
			     uint8_t        *wdata_p)
{
    // Convert size code to size in bytes
    uint8_t size_B = 0;
    switch (req_size_code) {
    case MEM_1B: size_B = 1; break;
    case MEM_2B: size_B = 2; break;
    case MEM_4B: size_B = 4; break;
    case MEM_8B: size_B = 8; break;
    default:
	fprintf (stdout, "ERROR: %s: bad req_size_code argument %0d\n",
		 __FUNCTION__, req_size_code);
	fprint_mem_req (stdout, inum, req_type, size_B, addr, wdata_p);
	exit (1);
    }

    const bool in_mem  = ((ADDR_BASE_MEM <= addr)
			  && ((addr + size_B) <= (ADDR_BASE_MEM + SIZE_B_MEM)));
    const bool in_UART = ((ADDR_BASE_UART <= addr)
			  && ((addr + size_B) <= (ADDR_BASE_UART + SIZE_B_UART)));
    const bool in_GPIO = ((ADDR_BASE_GPIO <= addr)
			  && ((addr + size_B) <= (ADDR_BASE_GPIO + SIZE_B_GPIO)));

    if (req_type == funct5_FENCE) {
	// These should only come from CLIENT_MMIO
	// For speculative accesses, FENCE is directly handled in mkStore_Buffer
	if (client != CLIENT_MMIO) {
	    fprintf (stdout, "ERROR: FENCE expecting CLIENT_MMIO");
	    fprintf_client (stdout, "; got ", client, "\n");
	    exit (1);
	}
	uint32_t *status_p = (uint32_t *) result_p;
	// No op for now
	*status_p = MEM_RSP_OK;
	return;
    }

    if ((! in_mem) && (! in_UART) && (! in_GPIO)) {
	// If speculative (CLIENT_DMEM) defer; else error
	uint32_t *status_p = (uint32_t *) result_p;
	if (client == CLIENT_DMEM)
	    *status_p = MEM_REQ_DEFERRED;
	else {
	    if (verbosity_wild != 0) {
		fprintf_client (stdout, "ERROR: c_mem_req(): wild address for ",
				client, "\n");
		fprint_mem_req (stdout, inum, req_type, size_B, addr, wdata_p);
	    }
	    *status_p = MEM_RSP_ERR;
	}
	return;
    }

    // Triage to mem/device units based on address
    if (in_mem) {
	c_access_mem (result_p, inum, req_type, size_B, addr, wdata_p, verbosity_mem);
	return;
    }

    if (in_UART) {
	if (verbosity_MMIO != 0) {
	    fprintf (stdout, "    In UART\n");
	    fprint_mem_req (stdout, inum, req_type, size_B, addr, wdata_p);
	}

	// Zero out read-data buffer
	uint32_t *status_p = (uint32_t *) result_p;
	uint8_t  *rdata_p  = & (result_p [4]);
	memset (rdata_p, 0, 8);

	if ((req_type != funct5_LOAD) && (req_type != funct5_STORE)) {
	    // Only allow LOAD/STORE ops
	    fprintf (stdout, "%s: UART req_type is not LOAD/STORE: %0x\n",
		     __FUNCTION__, req_type);
	    *status_p = MEM_RSP_ERR;
	}
	else {
	    if (verbosity_MMIO != 0) {
		fprintf (stdout, "    Perform UART MMIO\n");
	    }
	    uint8_t y;
	    int rc = UART_16550_try_mem_access (uart_p,
						rdata_p,
						(req_type == funct5_LOAD),
						addr,
						size_B,
						*wdata_p);
	    *status_p = ((rc == 0) ? MEM_RSP_OK : MEM_RSP_ERR);
	}
	return;
    }

    if (in_GPIO) {
	if (verbosity_MMIO != 0) {
	    fprintf (stdout, "    In GPIO\n");
	    fprint_mem_req (stdout, inum, req_type, size_B, addr, wdata_p);
	}

	// Zero out read-data buffer
	uint32_t *status_p = (uint32_t *) result_p;
	uint8_t  *rdata_p  = & (result_p [4]);
	memset (rdata_p, 0, 8);

	if ((req_type != funct5_LOAD) && (req_type != funct5_STORE)) {
	    // Only allow LOAD/STORE ops
	    fprintf (stdout, "%s: GPIO req_type is not LOAD/STORE: %0x\n",
		     __FUNCTION__, req_type);
	    *status_p = MEM_RSP_ERR;
	}
	else {
	    if (verbosity_MMIO != 0) {
		fprintf (stdout, "    Perform GPIO\n");
	    }
	    uint32_t *p = (uint32_t *) wdata_p;
	    uint32_t tohost_val = *p;
	    
	    if ((addr == (ADDR_BASE_GPIO + ADDR_OFFSET_GPIO_TOHOST))
		&& (req_type == funct5_STORE)
		&& (tohost_val & 0x1)) {

		if (rg_tohost != tohost_val) {
		    uint32_t testnum = (tohost_val >> 1);
		    if (testnum == 0) {
			fprintf (stdout, "\nGPIO tohost PASS\n");
			exit(0);
		    }
		    else {
			fprintf (stdout, "\nGPIO tohost FAIL on testnum %0d\n", testnum);
			exit(1);
		    }
		    rg_tohost = tohost_val;
		}
	    }

	    *status_p = MEM_RSP_OK;
	}
	return;
    }

    fprintf (stdout, "ERROR: %s: wild address, but previously checked ok\n",
	     __FUNCTION__);
    fprint_mem_req (stdout, inum, req_type, size_B, addr, wdata_p);
    exit (1);
}

// ****************************************************************
// ****************************************************************
// ****************************************************************
// Testing only
// Standalone test will load a memhex or ELF file.

/*
int main (int argc, char *argv [])
{
    c_mems_devices_init (0);
    return 0;
}
*/

// ****************************************************************
