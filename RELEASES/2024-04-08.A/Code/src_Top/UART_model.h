// Copyright (c) 2023-2024 Bluespec, Inc. All Rights Reserved
// Author: Rishiyur S. Nikhil
// Some fragments taken from earlier version of Cissr, 2013-2022 

#pragma once

// ****************************************************************
// Server on the System interconnect: UART

typedef  struct UART_16550_struct  UART_16550;

// ****************************************************************
// UART creation and initialization
// All regs are either 4- or 8-byte aligned (address-stride 4 or 8).

extern
UART_16550 *mkUART_16550 (const uint64_t addr_base, const uint8_t addr_stride);

// ****************************************************************
// UART interrupts

extern
bool irq_UART (UART_16550 *uart_p);

// ****************************************************************
// External API to assert reset, deassert reset

extern
void UART_16550_assert_reset (UART_16550 *uart_p);

extern
void UART_16550_deassert_reset (UART_16550 *uart_p);

// ****************************************************************
// 'tick' should be called regularly by the system, so that the UART
// can run "concurrently" with the system.  In tick(), can:
// * flush output buffer to screen if needed
// * read keyboard input is available for the input buffer
// * raise tx/rx interrupts if needed

void UART_16550_tick (UART_16550 *uart_p, const uint64_t tick_num);

// ****************************************************************
// The main MMIO function.
// Returns 0 (RC_OK) if no error; non-zero (RC_ERR) on error.

extern
int UART_16550_try_mem_access (UART_16550     *uart_p,
			       uint8_t        *rdata_p,
			       const bool      is_read,
			       const uint64_t  addr,
			       const uint8_t   size_B,
			       const uint8_t   wdata);



// ****************************************************************
