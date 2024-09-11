// ================================================================
// Copyright (c) 2024 Rishiyur S. Nikhil and Bluespec, Inc.  All Rights Reserved

// 'edb': Economical/Elementary Debugger

// ****************************************************************
// The 'bdpi_...' functions here are the only externally visible functions
// and are  imported into BSV using 'import "BDPI"' statements in BSV
// for Bluesim or Verilog simulation.

// ----------------
// Acknowledgements
//
// Portions of TCP code adapted from example ECHOSERV
//   ECHOSERV
//   (c) Paul Griffiths, 1999
//   http://www.paulgriffiths.net/program/c/echoserv.php
//

// Variants of this code have been used in other artefacts from
// Bluespec, Inc. such as AWSteria, Catamaran, ...

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

#include "Dbg_Pkts.h"

// ****************************************************************
// For debugging this code

int edbstub_verbosity = 0;

// ****************************************************************
// ****************************************************************
// ****************************************************************

// Functions for communication with client (EDB)

// ================================================================
// The socket file descriptors

static int listen_sockfd    = 0;
static int connected_sockfd = 0;

// ================================================================
// Check if connection is still up

static
void check_connection (int fd, const char *caller)
{
    struct pollfd  x_pollfd;
    x_pollfd.fd      = fd;
    x_pollfd.events  = 0;
    x_pollfd.revents = 0;

    poll (& x_pollfd, 1, 0);

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

static
void  host_listen (const uint16_t listen_port)
{
    struct sockaddr_in  servaddr;             // socket address structure
    struct linger       linger;
  
    fprintf (stdout, "Listening on tcp port %0d for debugger connection ...\n", listen_port);

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
    servaddr.sin_port        = htons (listen_port);

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

static
uint8_t host_try_accept ()
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
	fprintf (stdout, "Connection accepted\n");
	return 1;
    }
}

// ================================================================
// Disconnect from host as server.

static
void host_disconnect ()
{
    if (edbstub_verbosity != 0)
	fprintf (stdout, "Closing TCP connection\n");

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

// ****************************************************************
// Send/Receive packets
// Each of the two functions below has the native C version
// and a version for 'import BDPI' from BSV

// ================================================================
// Initialize this C module

void edbstub_init (uint16_t listen_port)
{
    host_listen (listen_port);

    while (true) {
	uint8_t ok = host_try_accept ();
	if (ok) break;
	sleep (1);
    }
}

// ----------------
// BSV view:
//   import "BDPI"
//   function Action bdpi_edbstub_init (Bit #(16) listen_port);

void bdpi_edbstub_init (uint16_t listen_port)
{
    edbstub_init (listen_port);
}

// ================================================================
// Shutdown this C module

void edbstub_shutdown ()
{
    fprintf (stdout, "Shutting down\n");
    host_disconnect ();
}

// ----------------
// BSV view:
//   import "BDPI"
//   function Action bdpi_edbstub_shutdown (Bit #(32) dummy);
// 'dummy' arg only to appease some Verilog simulators that are
//       finicky about 0-arg functions.

void bdpi_edbstub_shutdown (uint32_t dummy)
{
    edbstub_shutdown ();
}

// ================================================================
// Receive a packet from the debugger to the CPU, into to_CPU_pkt.
// If no packet received, return Dbg_to_CPU_NOOP in from_CPU_pkt.pkt_type

void edbstub_recv_to_CPU_pkt (Dbg_to_CPU_Pkt *p_pkt)
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
	p_pkt->pkt_type = Dbg_to_CPU_NOOP;
	return;    // No packet available
    }

    // Packet available; read it and return 1
    uint8_t *p_bytes = (uint8_t *) (p_pkt);
    int      n_recd  = 0;
    while (n_recd < sizeof (Dbg_to_CPU_Pkt)) {
	int n = read (fd, p_bytes + n_recd, (sizeof (Dbg_to_CPU_Pkt) - n_recd));

	if ((n < 0) && (errno != EAGAIN) && (errno != EWOULDBLOCK)) {
	    fprintf (stdout, "ERROR: %s: read () failed after %0d bytes\n",
		     __FUNCTION__, n_recd);
	    exit (1);
	}
	else if (n > 0) {
	    n_recd += n;
	}
	else {    // n == 0: EOF
	    fprintf (stdout, "Connection closed by remote debugger\n");
	    exit (1);
	}
    }
    if (edbstub_verbosity != 0) {
	print_to_CPU_pkt (stdout, "edbstub:received", p_pkt, "\n");
    }
}

// ----------------
// BSV view: recv, then convert struct to "standard size" words
//   import "BDPI"
//   function Vector #(3, Bit #(64)) bdpi_edbstub_recv_dbg_to_CPU_pkt ()

void bdpi_edbstub_recv_dbg_to_CPU_pkt (uint64_t *p_v)
{
    Dbg_to_CPU_Pkt pkt_in;
    edbstub_recv_to_CPU_pkt (& pkt_in);

    uint64_t v0 = 0;
    v0 =             (pkt_in.rw_size   & 0xFF);
    v0 = (v0 << 8) | (pkt_in.rw_op     & 0xFF);
    v0 = (v0 << 8) | (pkt_in.rw_target & 0xFF);
    v0 = (v0 << 8) | (pkt_in.pkt_type  & 0xFF);

    p_v [0] = v0;
    p_v [1] = pkt_in.rw_addr;
    p_v [2] = pkt_in.rw_wdata;
}

// ================================================================
// Send a 'dbg_from_CPU_pkt' to the remote debugger

void edbstub_send_dbg_from_CPU_pkt (const Dbg_from_CPU_Pkt *p_pkt_out)
{
    int  fd = connected_sockfd;

    if (edbstub_verbosity != 0) {
	print_from_CPU_pkt (stdout, "edbstub:sending", p_pkt_out, "\n");
    }

    uint8_t *p_bytes = (uint8_t *) (p_pkt_out);
    int      n_sent  = 0;
    while (n_sent < sizeof (Dbg_from_CPU_Pkt)) {
	int n = write (fd, p_bytes + n_sent, sizeof (Dbg_from_CPU_Pkt) - n_sent);
	if ((n < 0) && (errno != EAGAIN) && (errno != EWOULDBLOCK)) {
	    fprintf (stdout, "ERROR: %s: write () failed after %0d bytes\n",
		     __FUNCTION__, n_sent);
	    exit (1);
	}
	else if (n > 0) {
	    n_sent += n;
	}
    }
    fsync (fd);
}

// BSV view: convert "standard size" words into struct, then send
//   import "BDPI"
//   function Action bdpi_edbstub_send_dbg_from_CPU_pkt (Bit #(32) pkt_type, Bit #(64) x)

void bdpi_edbstub_send_dbg_from_CPU_pkt (uint32_t pkt_type, uint64_t x)
{
    Dbg_from_CPU_Pkt pkt_out;
    pkt_out.pkt_type = pkt_type;
    pkt_out.payload  = x;
    edbstub_send_dbg_from_CPU_pkt (& pkt_out);
}

// ****************************************************************
