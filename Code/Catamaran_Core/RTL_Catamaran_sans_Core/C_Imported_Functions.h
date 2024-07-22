// Copyright (c) 2016-2023 Bluespec, Inc.  All Rights Reserved

#pragma once

// ================================================================
// These are functions imported into BSV during Bluesim or Verilog simulation.
// See C_Imports.bsv for the corresponding 'import BDPI' declarations.

// There are several independent groups of functions below; the
// groups are separated by heavy dividers ('// *******')

// Below, 'dummy' args are not used, and are present only to appease
// some Verilog simulators that are finicky about 0-arg functions.

// Acknowledgement: portions of TCP code adapted from example ECHOSERV
//   ECHOSERV
//   (c) Paul Griffiths, 1999
//   http://www.paulgriffiths.net/program/c/echoserv.php

// ================================================================

#ifdef __cplusplus
extern "C" {
#endif

// ****************************************************************
// ****************************************************************
// ****************************************************************

// Functions to measure simulation speed

// ================================================================
// c_start_timing()
// Start the timing interval; argument is current cycle number.

extern
void c_start_timing (uint64_t  cycle_num);

// ================================================================
// c_end_timing()
// End the timing interval; argument is current cycle number,
// and print delta cycles, delta time and simulation speed.

extern
void c_end_timing (uint64_t  cycle_num);

// ****************************************************************
// ****************************************************************
// ****************************************************************

// Functions for console I/O

// ================================================================
// c_trygetchar()
// Returns next input character (ASCII code) from the console.
// Returns 0 if no input is available.

extern
uint8_t c_trygetchar (uint8_t  dummy);

// ================================================================
// c_putchar()
// Writes character to stdout

extern
uint32_t c_putchar (uint8_t ch);

// ****************************************************************
// ****************************************************************
// ****************************************************************

// Functions for communication with host-side

// ================================================================

extern
void  c_host_listen (const uint16_t tcp_port);

extern
uint8_t c_host_try_accept (uint8_t dummy);

extern
void c_host_disconnect (uint8_t dummy);

extern
void c_host_recv (uint8_t *bytevec, uint8_t bytevec_size);

extern
uint8_t c_host_recv2 (uint8_t dummy);

extern
uint8_t c_host_recv_get_byte_j (uint32_t j);

extern
void c_host_send (const uint8_t *bytevec, uint8_t bytevec_size);

extern
uint8_t c_host_send_put_byte_j (uint32_t j, uint8_t x);

extern
void c_host_send2 (uint8_t dummy);

// ****************************************************************
// ****************************************************************
// ****************************************************************

// Functions for Tandem Verification trace file output.

// ================================================================
// c_trace_file_open()
// Open file for recording binary trace output.

extern
uint32_t c_trace_file_open (uint8_t dummy);

// ================================================================
// c_trace_file_load_byte_in_buffer ()
// Write 8-bit 'data' into output buffer at byte offset 'j'

extern
uint32_t c_trace_file_load_byte_in_buffer (uint32_t j, uint8_t data);

// ================================================================
// c_trace_file_load_word64_in_buffer ()
// Write 64-bit 'data' into output buffer at 'byte_offset'

extern
uint32_t c_trace_file_load_word64_in_buffer (uint32_t byte_offset, uint64_t data);

// ================================================================
// c_trace_file_write_buffer()
// Write out 'n' bytes from the already-loaded output buffer to the trace file.

extern
uint32_t c_trace_file_write_buffer (uint32_t n);

// ================================================================
// c_trace_file_close()
// Close the trace file.

extern
uint32_t c_trace_file_close (uint8_t dummy);

// ****************************************************************
// ****************************************************************
// ****************************************************************

#ifdef __cplusplus
}
#endif
