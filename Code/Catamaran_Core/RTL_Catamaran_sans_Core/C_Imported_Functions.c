// Copyright (c) 2013-2023 Bluespec, Inc.  All Rights Reserved

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
// Includes from C library

// General
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <assert.h>

// For comms polling
#include <poll.h>

// For TCP
#include <sys/socket.h>       //  socket definitions
#include <sys/types.h>        //  socket types
#include <arpa/inet.h>        //  inet (3) funtions
#include <fcntl.h>            // To set non-blocking mode

// ================================================================
// Includes for this project

#include "C_Imported_Functions.h"

// ****************************************************************
// ****************************************************************
// ****************************************************************

// Functions to measure simulation speed

static uint64_t  start_cycle = 0;
static struct timespec timespec_start;

// ================================================================
// c_start_timing()
// Start the timing interval; argument is current cycle number.

extern
void c_start_timing (uint64_t  cycle_num)
{
    start_cycle = cycle_num;
    clock_gettime (CLOCK_REALTIME, & timespec_start);
}

// ================================================================
// c_end_timing()
// End the timing interval; argument is current cycle number,
// and print delta cycles, delta time and simulation speed.

extern
void c_end_timing (uint64_t  cycle_num)
{
    // Delta time
    struct timespec timespec_end;
    clock_gettime (CLOCK_REALTIME, & timespec_end);
    uint64_t nsecs1 = ((uint64_t) timespec_start.tv_sec) * 1000000000 + timespec_start.tv_nsec;
    uint64_t nsecs2 = ((uint64_t) timespec_end.tv_sec)   * 1000000000 + timespec_end.tv_nsec;
    uint64_t delta_nsecs = nsecs2 - nsecs1;

    // Delta cycles
    uint64_t delta_cycles = cycle_num - start_cycle;

    fprintf (stdout, "Simulation speed: %0" PRId64 " cycles, %0" PRId64 " nsecs", delta_cycles, delta_nsecs);
    if (delta_nsecs != 0)
	fprintf (stdout, "  = %0" PRId64 " cycles/sec", (delta_cycles * 1000000000) / delta_nsecs);
    fprintf (stdout, "\n");
}

// ****************************************************************
// ****************************************************************
// ****************************************************************

// Functions for console I/O

// ================================================================
// c_trygetchar()
// Returns next input character (ASCII code) from the console.
// Returns 0 if no input is available.

uint8_t c_trygetchar (uint8_t  dummy)
{
    uint8_t  ch;
    ssize_t  n;
    struct pollfd  x_pollfd;
    const int fd_stdin = 0;

    // ----------------
    // Poll for input
    x_pollfd.fd      = fd_stdin;
    x_pollfd.events  = POLLRDNORM;
    x_pollfd.revents = 0;
    poll (& x_pollfd, 1, 0);

    // printf ("INFO: %s: Polling for input\n", __FUNCTION__);
    if ((x_pollfd.revents & POLLRDNORM) == 0) {
	return 0;
    }

    // ----------------
    // Input is available

    n = read (fd_stdin, & ch, 1);
    if (n == 1) {
	return ch;
    }
    else {
	if (n == 0)
	    printf ("%s: end of file\n", __FUNCTION__);
	return 0xFF;
    }
}

// ================================================================
// A small 'main' to test c_trygetchar()

#ifdef TEST_TRYGETCHAR

char message[] = "Hello World!\n";

int main (int argc, char *argv [])
{
    uint8_t ch;
    int j;

    for (j = 0; j < strlen (message); j++)
	c_putchar (message[j]);

    printf ("Polling for input\n");

    j = 0;
    while (1) {
	ch = c_trygetchar (0);
	if (ch == 0xFF) break;
	if (ch != 0)
	    printf ("Received character %0d 0x%0x '%c'\n", ch, ch, ch);
	else {
	    printf ("\r%0d ", j);
	    fflush (stdout);
	    j++;
	    sleep (1);
	}
    }
    return 0;
}

#endif

// ================================================================
// c_putchar()
// Writes character to stdout

uint32_t c_putchar (uint8_t ch)
{
    int      status;
    uint32_t success = 0;

    if ((ch == 0) || (ch > 0x7F)) {
	// Discard non-printables
	success = 1;
    }
    else {
	if ((ch == '\n') || (' ' <= ch)) {
	    status = fprintf (stdout, "%c", ch);
	    if (status > 0)
		success = 1;
	}
	else {
	    status = fprintf (stdout, "[\\%0d]", ch);
	    if (status > 0)
		success = 1;
	}

	if (success == 1) {
	    status = fflush (stdout);
	    if (status != 0)
		success = 0;
	}
    }

    return success;
}

// ****************************************************************
// ****************************************************************
// ****************************************************************

// Functions for communication with host-side

// ================================================================
// The socket file descriptor

static int      listen_sockfd = 0;
static uint16_t listen_port   = 0;

static int      connected_sockfd = 0;

// ================================================================
// Check if connection is still up

static
void check_connection (int fd, const char *caller)
{
    struct pollfd  x_pollfd;
    x_pollfd.fd      = fd;
    x_pollfd.events  = 0;
    x_pollfd.revents = 0;

    int n = poll (& x_pollfd, 1, 0);

    if ((x_pollfd.revents & POLLHUP) != 0) {
	// Connection has been terminated by remote host (client)
	fprintf (stdout, "%s: terminated by remote host (POLLHUP); exiting\n",
		 __FUNCTION__);
	fprintf (stdout, "    during %s()\n", caller);
	exit (0);
    }
    if ((x_pollfd.revents & POLLERR) != 0) {
	// Connection has been terminated by remote host (client)
	fprintf (stdout, "%s: terminated by remote host (POLLERR); exiting\n",
		 __FUNCTION__);
	fprintf (stdout, "    during %s()\n", caller);
	exit (0);
    }
    if ((x_pollfd.revents & POLLNVAL) != 0) {
	// Connection has been terminated by remote host (client)
	fprintf (stdout, "%s: terminated by remote host (POLLNVAL); exiting\n",
		 __FUNCTION__);
	fprintf (stdout, "    during %s()\n", caller);
	exit (0);
    }
}

// ================================================================
// Start listening on a TCP server socket for a host (client) connection.

void  c_host_listen (const uint16_t tcp_port)
{
    struct sockaddr_in  servaddr;             // socket address structure
    struct linger       linger;
  
    /*
    fprintf (stdout, "%s: Listening on tcp port %0d for host connection ...\n",
	     __FUNCTION__, tcp_port);
    */

    // Create the listening socket
    if ( (listen_sockfd = socket (AF_INET, SOCK_STREAM, 0)) < 0 ) {
	fprintf (stderr, "ERROR: %s: socket () failed\n", __FUNCTION__);
	exit (1);
    }
  
    // Set linger to 0 (immediate exit on close)
    linger.l_onoff  = 1;
    linger.l_linger = 0;
    setsockopt (listen_sockfd, SOL_SOCKET, SO_LINGER, & linger, sizeof (linger));

    // Initialize socket address structure
    memset (& servaddr, 0, sizeof (servaddr));
    servaddr.sin_family      = AF_INET;
    servaddr.sin_addr.s_addr = htonl (INADDR_ANY);
    servaddr.sin_port        = htons (tcp_port);

    // Bind socket addresss to listening socket
    if ( bind (listen_sockfd, (struct sockaddr *) & servaddr, sizeof (servaddr)) < 0 ) {
	fprintf (stderr, "ERROR: %s: bind () failed\n", __FUNCTION__);
	exit (1);
    }

    // Listen for connection
    if ( listen (listen_sockfd, 1) < 0 ) {
	fprintf (stderr, "ERROR: %s: listen () failed\n", __FUNCTION__);
	exit (1);
    }

    // Set listening socket to non-blocking
    int flags = fcntl (listen_sockfd, F_GETFL, 0);
    if (flags < 0) {
	fprintf (stderr, "ERROR: %s: fcntl (F_GETFL) failed\n", __FUNCTION__);
	exit (1);
    }
    flags = (flags |O_NONBLOCK);
    if (fcntl (listen_sockfd, F_SETFL, flags) < 0) {
	fprintf (stderr, "ERROR: %s: fcntl (F_SETFL, O_NONBLOCK) failed\n", __FUNCTION__);
	exit (1);
    }
}

// ================================================================
// Try to accept a TCP connection from host (remote client)
// Return 1 on success, 0 if no pending connection

uint8_t c_host_try_accept (uint8_t dummy)
{
    connected_sockfd = accept (listen_sockfd, NULL, NULL);
    if ((connected_sockfd < 0) && ((errno == EAGAIN) || (errno == EWOULDBLOCK))) {
	// No pending connecction
	return 0;
    }
    else if (connected_sockfd < 0) {
	fprintf (stderr, "ERROR: %s: accept () failed\n", __FUNCTION__);
	exit (1);
    }
    else {
	// fprintf (stdout, "%s: Connection accepted\n", __FUNCTION__);
	return 1;
    }
}

// ================================================================
// Disconnect from host as server.
// Return fail/ok.

void c_host_disconnect (uint8_t dummy)
{
    fprintf (stdout, "%s: from host connection on port %0d\n", __FUNCTION__, listen_port);

    // Close the connected socket
    shutdown (connected_sockfd, SHUT_RDWR);
    if (close (connected_sockfd) < 0) {
	fprintf (stderr, "%s: close (connected_sockfd (= %0d)) failed\n",
		 __FUNCTION__, connected_sockfd);
	exit (1);
    }

    // Close the listening socket
    shutdown (listen_sockfd, SHUT_RDWR);
    if (close (listen_sockfd) < 0) {
	fprintf (stderr, "ERROR: %s: close (listen_sockfd) failed\n", __FUNCTION__);
	exit (1);
    }
}

// ================================================================
// Receive a packet from host-side.
// The stream of bytes is, logically, a sequence of packets.
// The packets may be of different size, up to a certain maximum
// (because there is a fixed repertoire of fixed-sized packets)
// For each 'packet' byte [0] indicate the 'packet' size
// An actual packet has at least 2 bytes (size, type).
// An actual packet must be smaller than 'size_bytes'.
// We return with [0] = 0 if no data is availble

void c_host_recv (uint8_t *bytevec, uint8_t bytevec_size)
{
    check_connection (connected_sockfd, __FUNCTION__);

    // ----------------
    // First, poll to check if any data is available
    int fd = connected_sockfd;

    struct pollfd  x_pollfd;
    x_pollfd.fd      = fd;
    x_pollfd.events  = POLLRDNORM;
    x_pollfd.revents = 0;

    int n = poll (& x_pollfd, 1, 0);

    if (n < 0) {
	fprintf (stdout, "ERROR: %s: poll () failed\n", __FUNCTION__);
	exit (1);
    }

    if ((x_pollfd.revents & POLLRDNORM) == 0) {
	// No byte available; return '0' in the bytevec [0]
	bytevec [0] = 0;
	return;
    }

    // ----------------
    // Data is available; read the first byte, which specifies # of bytes in the 'packet'

    int  data_size = 1;
    int  n_recd    = 0;
    while (n_recd < data_size) {
	int n = read (fd, & bytevec [n_recd], (data_size - n_recd));
	if ((n < 0) && (errno != EAGAIN) && (errno != EWOULDBLOCK)) {
	    fprintf (stdout, "ERROR: %s: read () failed on byte 0\n", __FUNCTION__);
	    exit (1);
	}
	else if (n > 0) {
	    n_recd += n;
	}
	else {    // n == 0: EOF
	    fprintf (stdout, "Connection closed by remote host (in %s())\n", __FUNCTION__);
	    exit (1);
	}
    }

    // ----------------
    // Read the remaining bytes

    data_size = bytevec [0];
    assert (data_size >= 2);
    assert (data_size <= bytevec_size);

    n_recd = 1;
    while (n_recd < data_size) {
	int n = read (fd, & bytevec [n_recd], (data_size - n_recd));
	if ((n < 0) && (errno != EAGAIN) && (errno != EWOULDBLOCK)) {
	    fprintf (stdout, "ERROR: %s: read () failed after %0d bytes\n", __FUNCTION__, n_recd);
	    exit (1);
	}
	else if (n > 0) {
	    n_recd += n;
	}
	else {    // n == 0: EOF
	    fprintf (stdout, "Connection closed by remote host (in %s())\n", __FUNCTION__);
	    exit (1);
	}
    }
}

// ================================================================
// Receive a packet from host-side.
// The stream of bytes is, logically, a sequence of packets.
// The packets may be of different size, up to a certain maximum
// (because there is a fixed repertoire of fixed-sized packets)
// For each 'packet' byte [0] indicate the 'packet' size
// An actual packet has at least 2 bytes (size, type).
// An actual packet must be smaller than 'size_bytes'.
// We return with [0] = 0 if no data is availble

#define C_HOST_RECV_BUF_SIZE 1024

static uint8_t c_host_recv_buf [C_HOST_RECV_BUF_SIZE];

uint8_t c_host_recv2 (uint8_t dummy)
{
    check_connection (connected_sockfd, __FUNCTION__);

    // ----------------
    // First, poll to check if any data is available
    int fd = connected_sockfd;

    struct pollfd  x_pollfd;
    x_pollfd.fd      = fd;
    x_pollfd.events  = POLLRDNORM;
    x_pollfd.revents = 0;

    int n = poll (& x_pollfd, 1, 0);

    if (n < 0) {
	fprintf (stdout, "ERROR: %s: poll () failed\n", __FUNCTION__);
	exit (1);
    }

    if ((x_pollfd.revents & POLLRDNORM) == 0) {
	// No byte available; return '0'
	return 0;    // No packet available
    }

    // ----------------
    // Data is available; read the first byte, which specifies # of bytes in the 'packet'

    int  data_size = 1;
    int  n_recd    = 0;
    while (n_recd < data_size) {
	int n = read (fd, & c_host_recv_buf [n_recd], (data_size - n_recd));
	if ((n < 0) && (errno != EAGAIN) && (errno != EWOULDBLOCK)) {
	    fprintf (stdout, "ERROR: %s: read () failed on byte 0\n", __FUNCTION__);
	    exit (1);
	}
	else if (n > 0) {
	    n_recd += n;
	}
	else {    // n == 0: EOF
	    fprintf (stdout, "Connection closed by remote host (in %s())\n", __FUNCTION__);
	    exit (1);
	}
    }

    // ----------------
    // Read the remaining bytes

    data_size = c_host_recv_buf [0];
    assert (data_size >= 2);
    assert (data_size <= C_HOST_RECV_BUF_SIZE);

    n_recd = 1;
    while (n_recd < data_size) {
	int n = read (fd, & c_host_recv_buf [n_recd], (data_size - n_recd));
	if ((n < 0) && (errno != EAGAIN) && (errno != EWOULDBLOCK)) {
	    fprintf (stdout, "ERROR: %s: read () failed after %0d bytes\n", __FUNCTION__, n_recd);
	    exit (1);
	}
	else if (n > 0) {
	    n_recd += n;
	}
	else {    // n == 0: EOF
	    fprintf (stdout, "Connection closed by remote host (in %s())\n", __FUNCTION__);
	    exit (1);
	}
    }

    // Zero out the rest of the buf
    for (int j = n_recd; j < C_HOST_RECV_BUF_SIZE; j++)
	c_host_recv_buf [j] = 0;

    return 1;    // Packet received
}

// ================================================================

uint8_t c_host_recv_get_byte_j (uint32_t j)
{
    if (j >= C_HOST_RECV_BUF_SIZE) {
	fprintf (stdout, "ERROR: %s(%0d): index out of bounds\n", __FUNCTION__, j);
	fprintf (stdout, "    Buf size is %0d\n", C_HOST_RECV_BUF_SIZE);
	exit (1);
    }
    return c_host_recv_buf [j];
}

// ================================================================
// This function is called from BSV to load a bytevec to send

#define C_HOST_SEND_BUF_SIZE 1024

static uint8_t c_host_send_buf [C_HOST_SEND_BUF_SIZE];

uint8_t c_host_send_put_byte_j (uint32_t j, uint8_t x)
{
    if (j >= C_HOST_SEND_BUF_SIZE) {
	fprintf (stdout, "ERROR: %s(%0d,%0d): index out of bounds\n", __FUNCTION__, j, x);
	fprintf (stdout, "    Buf size is %0d\n", C_HOST_SEND_BUF_SIZE);
	exit (1);
    }
    c_host_send_buf [j] = x;
    return 1;
}

// ================================================================
// Send the buffered bytevec to remote host
// bytevec [0] specifies # of bytes to send

void c_host_send2 (uint8_t dummy)
{
    int  fd = connected_sockfd;
    int  data_size;
    int  n_sent;

    data_size = c_host_send_buf [0];
    n_sent    = 0;
    while (n_sent < data_size) {
	int n = write (fd, & (c_host_send_buf [n_sent]), (data_size - n_sent));
	if ((n < 0) && (errno != EAGAIN) && (errno != EWOULDBLOCK)) {
	    fprintf (stdout, "ERROR: %s: write () failed after %0d bytes\n", __FUNCTION__, n_sent);
	    exit (1);
	}
	else if (n > 0) {
	    n_sent += n;
	}
    }
    fsync (fd);
}

// ================================================================
// Send a bytevec to remote host
// bytevec [0] specifies # of bytes to send

void c_host_send (const uint8_t *bytevec, uint8_t bytevec_size)
{
    int  fd = connected_sockfd;
    int  data_size;
    int  n_sent;

    data_size = bytevec [0];
    n_sent    = 0;
    while (n_sent < data_size) {
	int n = write (fd, & (bytevec [n_sent]), (data_size - n_sent));
	if ((n < 0) && (errno != EAGAIN) && (errno != EWOULDBLOCK)) {
	    fprintf (stdout, "ERROR: %s: write () failed after %0d bytes\n", __FUNCTION__, n_sent);
	    exit (1);
	}
	else if (n > 0) {
	    n_sent += n;
	}
    }
    fsync (fd);
}

// ================================================================
// This 'main' procedure is for standalone testing of this C server code.
// It listens on the server socket for a connection from the host.

#ifdef TEST

#define TEST_BUFSIZE 128

int main (int argc, char *argv [])
{
    c_host_connect (port);

    uint8_t buffer [TEST_BUFSIZE];

    while (true) {
	c_host_recv (buffer, TEST_BUFSIZE);

	uint16_t size = buffer [1];
	size = (size << 8) + buffer [0];
	if (size == 0) {
	    fprintf (stdout, "No packet avail (size = 0)\n");
	    usleep (1000000);
	}
	else if (size < 3)
	    fprintf (stdout, "Receive error (size = %0d)\n", size);
	else {
	    fprintf (stdout, "Received: size = %0d\n    ", size);
	    if (size > TEST_BUFSIZE) {
		fprintf (stdout, "    Size is greater than buffer size (%0d)\n", TEST_BUFSIZE);
		size = TEST_BUFSIZE;
	    }
	    for (int j = 2; j < size; j++) {
		fprintf (stdout, " %02d", buffer [j]);
	    }
	    fprintf (stdout, "\n");
	}
    }
    return 0;
}

#endif

// ****************************************************************
// ****************************************************************
// ****************************************************************

// Functions for Tandem Verification trace file output.

static char trace_file_name[] = "trace_data.dat";

static FILE *trace_file_stream;

static uint64_t trace_file_size   = 0;
static uint64_t trace_file_writes = 0;

#define BUFSIZE 1024
static uint8_t buf [BUFSIZE];

// ================================================================
// c_trace_file_open()
// Open file for recording binary trace output.

uint32_t c_trace_file_open (uint8_t dummy)
{
    uint32_t success = 0;

    trace_file_stream = fopen ("trace_out.dat", "w");
    if (trace_file_stream == NULL) {
	fprintf (stderr, "ERROR: %s: unable to open file '%s'.\n", __FUNCTION__, trace_file_name);
	success = 0;
    }
    else {
	fprintf (stdout, "%s: opened file '%s' for trace_data.\n", __FUNCTION__, trace_file_name);
	success = 1;
    }
    return success;
}

// ================================================================
// c_trace_file_load_byte_in_buffer ()
// Write 8-bit 'data' into output buffer at byte offset 'j'

uint32_t c_trace_file_load_byte_in_buffer (uint32_t j, uint8_t data)
{
    uint32_t success = 0;

    if (j >= BUFSIZE) {
	fprintf (stderr, "ERROR: %s: index (%0d) out of bounds (%0d)\n",
		 __FUNCTION__, j, BUFSIZE);
	success = 0;
    }
    else {
	buf [j] = data;
	success = 1;
    }
    return success;
}

// ================================================================
// c_trace_file_load_word64_in_buffer ()
// Write 64-bit 'data' into output buffer at 'byte_offset'

uint32_t c_trace_file_load_word64_in_buffer (uint32_t byte_offset, uint64_t data)
{
    uint32_t success = 0;

    if ((byte_offset + 7) >= BUFSIZE) {
	fprintf (stderr, "ERROR: %s: index (%0d) out of bounds (%0d)\n",
		 __FUNCTION__, byte_offset, BUFSIZE);
	success = 0;
    }
    else {
	uint64_t *p = (uint64_t *) & (buf [byte_offset]);
	*p = data;
	success = 1;
    }
    return success;
}

// ================================================================
// c_trace_file_write_buffer()
// Write out 'n' bytes from the already-loaded output buffer to the trace file.

uint32_t c_trace_file_write_buffer (uint32_t n)
{
    uint32_t success = 0;

    size_t n_written = fwrite (buf, 1, n, trace_file_stream);
    if (n_written != n)
	success = 0;
    else {
	trace_file_size   += n;
	trace_file_writes += 1;
	success = 1;
    }
    return success;
}

// ================================================================
// c_trace_file_close()
// Close the trace file.

uint32_t c_trace_file_close (uint8_t dummy)
{
    uint32_t success = 0;
    int      status;

    if (trace_file_stream == NULL)
	success = 1;
    else {
	status = fclose (trace_file_stream);
	if (status != 0) {
	    fprintf (stderr, "ERROR: %s: error in fclose()\n", __FUNCTION__);
	    success = 0;
	}
	else {
	    fprintf (stdout, "%s: closed file '%s' for trace_data.\n",
		     __FUNCTION__, trace_file_name);
	    fprintf (stdout, "    Trace file writes: %0" PRId64 "\n", trace_file_writes);
	    fprintf (stdout, "    Trace file size:   %0" PRId64 " bytes\n", trace_file_size);
	    success = 1;
	}
    }
    return success;
}

// ****************************************************************
// ****************************************************************
// ****************************************************************
