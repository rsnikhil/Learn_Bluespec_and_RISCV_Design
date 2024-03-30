// Copyright (c) 2023-2024 Bluespec, Inc. All Rights Reserved
// Author: Rishiyur S. Nikhil
// Some fragments taken from earlier version of Cissr, 2013-2022 

// ****************************************************************
// Server on the System interconnect: UART

// ****************************************************************

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <stdbool.h>
#include <assert.h>
#include <poll.h>

#include "UART_model.h"

// ****************************************************************

static const int verbosity = 0;

typedef enum {RC_OK, RC_ERR} RC;    // function return-code

// ****************************************************************
// UART registers and their address offsets

const uint8_t  addr_UART_rbr  = 0x0;    // receiver buffer register (read only)
const uint8_t  addr_UART_thr  = 0x0;    // transmitter holding register (write only)
const uint8_t  addr_UART_ier  = 0x1;    // interrupt enable register
const uint8_t  addr_UART_iir  = 0x2;    // interrupt id register    (read-only)
const uint8_t  addr_UART_lcr  = 0x3;    // line control reg
const uint8_t  addr_UART_mcr  = 0x4;    // modem control reg
const uint8_t  addr_UART_lsr  = 0x5;    // line status reg     (read-only)
const uint8_t  addr_UART_msr  = 0x6;    // modem status reg    (read-only)
const uint8_t  addr_UART_scr  = 0x7;    // scratch pad reg

// Aliased registers, depending on control bits
const uint8_t  addr_UART_dll  = 0x0;    // divisor latch low
const uint8_t  addr_UART_dlm  = 0x1;    // divisor latch high
const uint8_t  addr_UART_fcr  = 0x2;    // fifo control reg    (write-only)

// Bit fields of ier (Interrupt Enable Register)
const uint8_t  uart_ier_erbfi = 0x01;     // Enable Received Data Available Interrupt
const uint8_t  uart_ier_etbei = 0x02;     // Enable Transmitter Holding Register Empty Interrupt
const uint8_t  uart_ier_elsi  = 0x04;     // Enable Receiver Line Status Interrupt
const uint8_t  uart_ier_edssi = 0x08;     // Enable Modem Status Interrupt

// iir values (Interrupt Identification Register) in decreasing priority of interrupts
const uint8_t  uart_iir_none  = 0x01;     // None (no interrupts pending)
const uint8_t  uart_iir_rls   = 0x06;     // Receiver Line Status
const uint8_t  uart_iir_rda   = 0x04;     // Received Data Available
const uint8_t  uart_iir_cti   = 0x0C;     // Character Timeout Indication
const uint8_t  uart_iir_thre  = 0x02;     // Transmitter Holding Register Empty
const uint8_t  uart_iir_ms    = 0x00;     // Modem Status

// Bit fields of LCR
const uint8_t  uart_lcr_dlab  = 0x80;     // Divisor latch access bit
const uint8_t  uart_lcr_bc    = 0x40;     // Break control
const uint8_t  uart_lcr_sp    = 0x20;     // Stick parity
const uint8_t  uart_lcr_eps   = 0x10;     // Even parity
const uint8_t  uart_lcr_pen   = 0x08;     // Parity enable
const uint8_t  uart_lcr_stb   = 0x04;     // # of stop bits (0=1b,1=2b)
const uint8_t  uart_lcr_wls   = 0x03;     // word len (0:5b,1:6b,2:7b,3:8b)

// Bit fields of LSR (line status reg)
const uint8_t  uart_lsr_rxfe  = 0x80;    // Receiver FIFO error
const uint8_t  uart_lsr_temt  = 0x40;    // Transmitter empty
const uint8_t  uart_lsr_thre  = 0x20;    // THR empty
const uint8_t  uart_lsr_bi    = 0x10;    // Break interrupt
const uint8_t  uart_lsr_fe    = 0x08;    // Framing Error
const uint8_t  uart_lsr_pe    = 0x04;    // Parity Error
const uint8_t  uart_lsr_oe    = 0x02;    // Overrun Error
const uint8_t  uart_lsr_dr    = 0x01;    // Data Ready

const uint8_t  uart_lsr_reset_value = (uart_lsr_temt | uart_lsr_thre);

// ****************************************************************
// In the 'tick' function below, we poll for UART input relatively
// infrequently; specifically, when tick_num & mask == 0.

// WARNING: Linux boot seems quite sensitive to this frequency.  If
// too small, Linux seems to drop UART chars, miss UART interrupts,
// etc.  Of course, if too big, there may be noticeable latency in
// providing input to Linux.

#define UART_INPUT_POLL_FREQUENCY_MASK  0x3FFFF

// ****************************************************************

struct UART_16550_struct {
    uint8_t  rg_rbr;    // addr offset 0
    uint8_t  rg_thr;    // addr offset 0
    uint8_t  rg_dll;    // addr offset 0

    uint8_t  rg_ier;    // addr offset 1
    uint8_t  rg_dlm;    // addr offset 1

    // IIR is a virtual read-only register computed from other regs
    uint8_t  rg_fcr;    // addr offset 2

    uint8_t  rg_lcr;    // addr offset 3
    uint8_t  rg_mcr;    // addr offset 4
    uint8_t  rg_lsr;
    uint8_t  rg_msr;    // addr offset 6
    uint8_t  rg_scr;    // addr offset 7

    uint64_t addr_base;
    uint8_t  addr_stride;

    // To detect posedge of irq
    bool last_irq;

    // Buffer for input chars (keyboard -> UART -> CPU)
#define IN_LINEBUF_SIZE 128
    char     in_linebuf [IN_LINEBUF_SIZE];
    int      in_linebuf_len;
    int      in_linebuf_next;

    // Buffer for output chars (CPU -> UART -> screen)
#define OUT_LINEBUF_SIZE 128
    uint8_t out_linebuf [OUT_LINEBUF_SIZE];
    int     out_linebuf_next;
    int     out_linebuf_update_tick;
};

// ----------------
// Virtual read-only register IIR (interrupt identification register)

inline
static
uint8_t fn_iir (UART_16550 *uart_p)
{
    uint8_t iir = uart_iir_none;

    if (((uart_p->rg_ier & uart_ier_erbfi) != 0)    // Rx interrupt enabled
	&& ((uart_p->rg_lsr & uart_lsr_dr) != 0))   // data ready
	iir = uart_iir_rda;

    else if ((uart_p->rg_ier & uart_ier_etbei) != 0) {
	// Tx Holding Reg Empty intr enabled
	iir = uart_iir_thre;
    }

    return iir;
}

// ****************************************************************
// UART creation and initialization
// All regs are either 4- or 8-byte aligned (address-stride 4 or 8).

UART_16550 *mkUART_16550 (const uint64_t addr_base, const uint8_t addr_stride)
{
    if ((addr_stride != 4) && (addr_stride != 8)) {
	fprintf (stdout, "ERROR: %s(): addr_stride (%0d) should be 4 or 8 only\n",
		 __FUNCTION__, addr_stride);
	exit (1);
    }

    UART_16550 *uart_p = (UART_16550 *) malloc (sizeof (UART_16550));
    if (uart_p == NULL) {
	fprintf (stdout, "INTERNAL ERROR: %s(): malloc failed for UART_16550\n",
		 __FUNCTION__);
	exit (1);
    }
    memset (uart_p, 0, sizeof (UART_16550));

    uart_p->addr_base   = addr_base;
    uart_p->addr_stride = addr_stride;

    UART_16550_assert_reset (uart_p);
    UART_16550_deassert_reset (uart_p);

    return uart_p;
}

// ****************************************************************
// UART interrupts

bool irq_UART (UART_16550 *uart_p)
{
    const uint8_t iir = fn_iir (uart_p);
    const bool    irq = ((iir & uart_iir_none) == 0);
    const bool    result = ((! uart_p->last_irq) && irq);

    if (result && (verbosity != 0))
	fprintf (stdout, "%s(): (0->1)\n", __FUNCTION__);

    uart_p->last_irq = irq;
    return result;
}

// ****************************************************************
// External API to assert reset, deassert reset

void UART_16550_assert_reset (UART_16550 *uart_p)
{
    if (verbosity != 0)
	fprintf (stdout, "%s\n", __FUNCTION__);

    uart_p->rg_dll = 0;
    uart_p->rg_ier = 0;
    uart_p->rg_dlm = 0;
    uart_p->rg_fcr = 0;
    uart_p->rg_lcr = 0;
    uart_p->rg_mcr = 0;
    uart_p->rg_lsr = uart_lsr_reset_value;
    uart_p->rg_msr = 0;
    uart_p->rg_scr = 0;

    uart_p->in_linebuf_len  = 0;
    uart_p->in_linebuf_next = 0;

    uart_p->out_linebuf_next        = 0;
    uart_p->out_linebuf_update_tick = 0;

    uart_p->last_irq = false;
}

void UART_16550_deassert_reset (UART_16550 *uart_p)
{
    if (verbosity != 0)
	fprintf (stdout, "%s()\n", __FUNCTION__);

    // no-op
}

// ****************************************************************
// 'tick' should be called regularly by the system, so that the UART
// can run "concurrently" with the system.  In tick(), can:
// * flush output buffer to screen if needed
// * read keyboard input is available for the input buffer
// * raise tx/rx interrupts if needed

// ----------------
// Test if input from keyboard is available

inline
static
bool input_is_available (const int fd)
{
    struct pollfd  x_pollfd;

    x_pollfd.fd      = fd;
    x_pollfd.events  = POLLRDNORM;
    x_pollfd.revents = 0;
    poll (& x_pollfd, 1, 0);

    return ((x_pollfd.revents & POLLRDNORM) != 0);
}

// This is a forward declaration
int UART_16550_receive_from_serial_line (UART_16550 *uart_p, const uint8_t ch);

static uint64_t global_tick_num = 0;

void UART_16550_tick (UART_16550 *uart_p, const uint64_t tick_num)
{
    global_tick_num++;

    // Output chars: flush out_linebuf if chars pending for some time
    const int AGE_FLUSH_THRESHOLD = 100;
    if ((uart_p->out_linebuf_next != 0)
	&& ((global_tick_num - uart_p->out_linebuf_update_tick) > AGE_FLUSH_THRESHOLD)) {
	uart_p->out_linebuf [uart_p->out_linebuf_next] = 0;
	fprintf (stdout, "%s", uart_p->out_linebuf);
	fflush (stdout);

	uart_p->out_linebuf_next = 0;
	uart_p->out_linebuf_update_tick = global_tick_num;
    }

    // ----------------
    // Input chars (keyboard -> UART)

    if ((global_tick_num & UART_INPUT_POLL_FREQUENCY_MASK) == 0) {

	// If in_linebuf is empty; try refill it from keyboard
	if (uart_p->in_linebuf_next >= uart_p->in_linebuf_len) {
	    const int fd_stdin = fileno (stdin);
	    if (input_is_available (fd_stdin)) {
		const char *p = fgets (& (uart_p->in_linebuf [0]), IN_LINEBUF_SIZE, stdin);
		if (p == NULL) {
		    fprintf (stdout, "EOF on stdin; quitting\n");
		    exit (1);
		}
		uart_p->in_linebuf_len  = strlen (p);
		uart_p->in_linebuf_next = 0;
	    }
	}

	// If in_linebuf is non-empty, try to feed UART
	if (uart_p->in_linebuf_next < uart_p->in_linebuf_len) {
	    const uint8_t ch = uart_p->in_linebuf [uart_p->in_linebuf_next];
	    int rc = UART_16550_receive_from_serial_line (uart_p, ch);
	    if (rc == RC_OK)
		uart_p->in_linebuf_next++;
	}
    }
}

// ****************************************************************
// External API for serial line to deposit a char into the UART
// Return RC_OK if successfull, RC_ERR otherwise (RBR is not empty)

int UART_16550_receive_from_serial_line (UART_16550 *uart_p, const uint8_t ch)
{
    const bool rbr_is_empty = ((uart_p->rg_lsr & uart_lsr_dr) == 0);
    if (rbr_is_empty) {
	uart_p->rg_rbr  = ch;
	uint8_t new_lsr = (uart_p->rg_lsr | uart_lsr_dr);    // set data-ready
	uart_p->rg_lsr  = new_lsr;
	return RC_OK;
    }
    else {
	fprintf (stdout, "WARNING: UART: %s: rg_rbr is not empty; ch is:", __FUNCTION__);
	if (ch <= ' ')
	    fprintf (stdout, " 0x%0x\n", ch);
	else
	    fprintf (stdout, " '%c'\n", ch);
	return RC_ERR;
    }
}

// ****************************************************************
// MMIO access to the UART.

// ----------------
// For debugging

static
void fprintf_Mem_Req (FILE *fout,
		      const char     *pre,
		      const bool      is_read,
		      const uint64_t  addr,
		      const uint8_t   size_B,
		      const uint8_t   wdata,
		      const char     *post)
{
    fprintf (fout, "%s", pre);
    fprintf (fout, "UART Mem_Req{");
    if (is_read) fprintf (fout, "LOAD");
    else fprintf (fout, "STORE");
    fprintf (fout, " addr:%08" PRIx64, addr);
    fprintf (fout, " size_B:%0d",      size_B);
    if (! is_read)
	fprintf (fout, " wdata:%02x", wdata);
    fprintf (fout, "}");
    fprintf (fout, "%s", post);
}

// ----------------
// UART registers are 1-byte wide, but MMIO requests can be 1,2, or 4
// bytes, or 8 bytes if addr_stride is 8.
// (We use only the LSB).

inline
static
bool ok_size (const UART_16550 *uart_p, const uint8_t size_B)
{

    if ((size_B == 1)
	|| (size_B == 2)
	|| (size_B == 4)
	|| ((size_B == 8) && (uart_p->addr_stride == 8))) {
	return true;
    }
    else {
	fprintf (stdout, "ERROR: UART: %s: Bad mem req size %0d\n", __FUNCTION__, size_B);
	return false;
    }
}

// ----------------
// Is MMIO request addr aligned to addr_stride?

inline
static
bool ok_alignment (const UART_16550 *uart_p, const uint64_t    addr)
{
    if ((uart_p->addr_stride == 4) && ((addr & 0x3) == 0))
	return true;
    else if ((uart_p->addr_stride == 8) && ((addr & 0x7) == 0))
	return true;
    else {
	fprintf (stdout, "ERROR: UART: %s: Misaligned", __FUNCTION__);
	fprintf (stdout, " addr:%08" PRIx64 " for addr_stride_B:%0d\n",
		 addr, uart_p->addr_stride);
	return false;
    }
}

// ****************************************************************
// The main MMIO function.
// Returns 0 (RC_OK) if no error; non-zero (RC_ERR) on error.

int UART_16550_try_mem_access (UART_16550     *uart_p,
			       uint8_t        *rdata_p,
			       const bool      is_read,
			       const uint64_t  addr,
			       const uint8_t   size_B,
			       const uint8_t   wdata)
{
    if (verbosity != 0)
	fprintf_Mem_Req (stdout, "", is_read, addr, size_B, wdata, "\n");

    if (! ok_size       (uart_p, size_B)) return RC_ERR;
    if (! ok_alignment  (uart_p, addr))   return RC_ERR;

    uint8_t  uart_reg_num;
    if (uart_p->addr_stride == 4)
	uart_reg_num = ((addr - uart_p->addr_base) >> 2) & 0x7;
    else
	uart_reg_num = ((addr - uart_p->addr_base) >> 3) & 0x7;

    if (uart_reg_num > addr_UART_scr) {
	fprintf (stdout, "ERROR: UART: %s: wild address\n", __FUNCTION__);
	fprintf (stdout, "    req  addr:      %08" PRIx64 "\n", addr);
	fprintf (stdout, "    UART addr_base: %08" PRIx64 "\n", uart_p->addr_base);
	return RC_ERR;
    }

    // ----------------

    int rc = RC_OK;

    if (is_read) {
	uint8_t  rdata = 0;

	if ((uart_reg_num == addr_UART_rbr)
	    && ((uart_p->rg_lcr & uart_lcr_dlab) == 0)) {
	    // Read an input char
	    if (verbosity != 0)
		fprintf (stdout,
			 "    UART reg RBR (0 when lcr_dlab == 0)\n");

	    uart_p->rg_lsr = (uart_p->rg_lsr & (~ uart_lsr_dr));    // Reset data-ready
	    rdata = uart_p->rg_rbr;
	}
	else if ((uart_reg_num == addr_UART_dll)
		 && ((uart_p->rg_lcr & uart_lcr_dlab) != 0)) {
	    if (verbosity != 0)
		fprintf (stdout,
			 "    UART reg DLL (0 when lcr_dlab == 1)\n");
	    rdata = uart_p->rg_dll;
	}
	else if ((uart_reg_num == addr_UART_ier)
		 && ((uart_p->rg_lcr & uart_lcr_dlab) == 0)) {
	    if (verbosity != 0)
		fprintf (stdout,
			 "    UART reg IER (1 when lcr_dlab == 0)\n");
	    rdata = uart_p->rg_ier;
	}
	else if ((uart_reg_num == addr_UART_dlm)
		 && ((uart_p->rg_lcr & uart_lcr_dlab) != 0)) {
	    if (verbosity != 0)
		fprintf (stdout,
			 "    UART reg DLM (1 when lcr_dlab == 1)\n");
	    rdata = uart_p->rg_dlm;
	}

	else if (uart_reg_num == addr_UART_iir) {
	    if (verbosity != 0)
		fprintf (stdout, "    UART reg IIR (2)\n");
	    rdata = fn_iir (uart_p);
	}
	else if (uart_reg_num == addr_UART_lcr) {
	    if (verbosity != 0)
		fprintf (stdout, "    UART reg LCR (3)\n");
	    rdata = uart_p->rg_lcr;
	}
	else if (uart_reg_num == addr_UART_mcr) {
	    if (verbosity != 0)
		fprintf (stdout, "    UART reg LCR (4)\n");
	    rdata = uart_p->rg_mcr;
	}
	else if (uart_reg_num == addr_UART_lsr) {     // line status reg
	    if (verbosity != 0)
		fprintf (stdout, "    UART reg LSR (5)\n");
	    rdata = uart_p->rg_lsr;
	}
	else if (uart_reg_num == addr_UART_msr) {
	    if (verbosity != 0)
		fprintf (stdout, "    UART reg MSR (6)\n");
	    rdata = uart_p->rg_msr;
	}
	else if (uart_reg_num == addr_UART_scr) {
	    if (verbosity != 0)
		fprintf (stdout, "    UART reg SCR (7)\n");
	    rdata = uart_p->rg_scr;
	}

	else {
	    fprintf (stdout, "ERROR: %s: unrecognized UART reg num %0d\n",
		     __FUNCTION__, uart_reg_num);
	    return RC_ERR;
	}
	*rdata_p = rdata;

	if (verbosity != 0) {
	    fprintf (stdout, "    read-response: %02x\n", rdata);
	}
    }

    else {
	// ! is_read (i.e., STORE)

	if ((uart_reg_num == addr_UART_thr) && ((uart_p->rg_lcr & uart_lcr_dlab) == 0)) {
	    if (verbosity != 0)
		fprintf (stdout,
			 "    UART reg THR (0 when lcr_dlab == 0)\n");

	    // Overwrite char to THR (in this model, we don't use THR)
	    uart_p->rg_thr = wdata;

	    if (verbosity != 0) {
		fprintf (stdout,
			 "UART ASCII output:  0x%0x  %0d", wdata, wdata);
		if ((' ' <= wdata) && (wdata < 0x80))
		    fprintf (stdout, "  '%c'", wdata);
		fprintf (stdout, "\n");
	    }

	    // Write the char to the output line buffer
	    uart_p->out_linebuf [uart_p->out_linebuf_next] = wdata;
	    uart_p->out_linebuf_next++;
	    uart_p->out_linebuf_update_tick = global_tick_num;
	    if ((wdata == '\n')
		|| ((uart_p->out_linebuf_next + 1) == OUT_LINEBUF_SIZE)) {
		uart_p->out_linebuf [uart_p->out_linebuf_next] = 0;
		fprintf (stdout, "%s", uart_p->out_linebuf);
		uart_p->out_linebuf_next = 0;
	    }
	}
	else if ((uart_reg_num == addr_UART_dll)
		 && ((uart_p->rg_lcr & uart_lcr_dlab) != 0)) {
	    if (verbosity != 0)
		fprintf (stdout,
			 "    UART reg DLL (0 when lcr_dlab == 1)\n");
	    uart_p->rg_dll = wdata;
	}
	else if ((uart_reg_num == addr_UART_ier)
		 && ((uart_p->rg_lcr & uart_lcr_dlab) == 0)) {
	    if (verbosity != 0)
		fprintf (stdout,
			 "    UART reg IER (1 when lcr_dlab == 0)\n");
	    uart_p->rg_ier = wdata;
	}
	else if ((uart_reg_num == addr_UART_dlm)
		 && ((uart_p->rg_lcr & uart_lcr_dlab) != 0)) {
	    if (verbosity != 0)
		fprintf (stdout,
			 "    UART reg DLM (1 when lcr_dlab == 1)\n");
	    uart_p->rg_dlm = wdata;
	}
	else if (uart_reg_num == addr_UART_fcr) {
	    if (verbosity != 0)
		fprintf (stdout, "    UART reg FCR (2)\n");
	    uart_p->rg_fcr = wdata;
	}
	else if (uart_reg_num == addr_UART_lcr) {
	    if (verbosity != 0)
		fprintf (stdout, "    UART reg LCR (3)\n");
	    uart_p->rg_lcr = wdata;
	}
	else if (uart_reg_num == addr_UART_mcr) {
	    if (verbosity != 0)
		fprintf (stdout, "    UART reg MCR (4)\n");
	    uart_p->rg_mcr = wdata;
	}
	else if (uart_reg_num == addr_UART_lsr) {      // LSR is read-only
	    if (verbosity != 0)
		fprintf (stdout, "    UART reg LSR (5)\n");
	}
	else if (uart_reg_num == addr_UART_msr) {      // MSR is read-only
	    if (verbosity != 0)
		fprintf (stdout, "    UART reg MSR (6)\n");
	}
	else if (uart_reg_num == addr_UART_scr) {
	    if (verbosity != 0)
		fprintf (stdout, "    UART reg SCR (7)\n");
	    uart_p->rg_scr = wdata;
	}
	else {
	    fprintf (stdout, "ERROR: %s: unrecognized UART reg num %0d\n",
		     __FUNCTION__, uart_reg_num);

	    return RC_ERR;
	}
    }

    return RC_OK;
}

// ****************************************************************
