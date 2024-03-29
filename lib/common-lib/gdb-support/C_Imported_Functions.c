// Copyright (c) 2013-2019 Bluespec, Inc.  All Rights Reserved

// ================================================================
// These are functions imported into BSV during Bluesim or Verilog simulation.
// See C_Imports.bsv for the corresponding 'import BDPI' declarations.

// There are several independent groups of functions below; the
// groups are separated by heavy dividers ('// *******')

// Below, 'dummy' args are not used, and are present only to appease
// some Verilog simulators that are finicky about 0-arg functions.

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

// For comms polling
#include <sys/types.h>
#include <poll.h>
#include <sched.h>

// For TCP
#include <sys/socket.h>       //  socket definitions
#include <sys/types.h>        //  socket types
#include <arpa/inet.h>        //  inet (3) funtions
#include <netinet/in.h>
#include <fcntl.h>            // To set non-blocking mode
#include <sys/un.h>

// ================================================================
// Includes for this project

#include "C_Imported_Functions.h"

// ****************************************************************
// ****************************************************************
// ****************************************************************

// Functions for communication with remote debug client.

// Acknowledgement: portions of TCP code adapted from example ECHOSERV
//   ECHOSERV
//   (c) Paul Griffiths, 1999
//   http://www.paulgriffiths.net/program/c/echoserv.php

// ================================================================
// The socket file descriptor

static uint16_t port = 30000;

static int connected_sockfd = 0;

static FILE *logfile_fp = NULL;

static char logfile_name [] = "debug_server_log.txt";

static const char unix_socket_file[] = "gdb/unix_socket/dm_stub_";

// ================================================================
// Connect to debug client as server on tcp_port.
// Return fail/ok.

uint8_t  c_debug_client_connect (const uint16_t tcp_port)
{
    int                 listen_sockfd;        // listening socket
    struct sockaddr_un  servaddr;             // socket address structure
    struct linger       linger;
  
  	fprintf (stdout, "Working on unix socket: %s%d  ...\n", unix_socket_file, tcp_port);
    fprintf (stdout, "Awaiting remote debug client connection on tcp port %0d ...\n", tcp_port);

    // Create the listening socket
    if ( (listen_sockfd = socket (AF_UNIX, SOCK_STREAM, 0)) < 0 ) {
	fprintf (stderr, "ERROR: c_debug_client_connect: socket () failed\n");
	return DMI_STATUS_ERR;
    }
  
    // Set linger to 0 (immediate exit on close)
    linger.l_onoff  = 1;
    linger.l_linger = 0;
    setsockopt (listen_sockfd, SOL_SOCKET, SO_LINGER, & linger, sizeof (linger));

    // Initialize socket address structure
    memset (& servaddr, 0, sizeof (servaddr));
	servaddr.sun_family = AF_UNIX;
	sprintf(servaddr.sun_path, "%s%d", unix_socket_file, tcp_port);

    // Bind socket addresss to listening socket
    if ( bind (listen_sockfd, (struct sockaddr *) & servaddr, sizeof (servaddr)) < 0 ) {
	fprintf (stderr, "ERROR: c_debug_client_connect: bind () failed\n");
	return DMI_STATUS_ERR;
    }

    // Listen for connection
    if ( listen (listen_sockfd, 1) < 0 ) {
	fprintf (stderr, "ERROR: c_debug_client_connect: listen () failed\n");
	return DMI_STATUS_ERR;
    }

    // Set listening socket to non-blocking
    int flags = fcntl (listen_sockfd, F_GETFL, 0);
    if (flags < 0) {
	fprintf (stderr, "ERROR: c_debug_client_connect: fcntl (F_GETFL) failed\n");
	return DMI_STATUS_ERR;
    }
    flags = (flags |O_NONBLOCK);
    if (fcntl (listen_sockfd, F_SETFL, flags) < 0) {
	fprintf (stderr, "ERROR: c_debug_client_connect: fcntl (F_SETFL, O_NONBLOCK) failed\n");
	return DMI_STATUS_ERR;
    }

    // Wait for a connection, accept() it
    while (true) {
	connected_sockfd = accept (listen_sockfd, NULL, NULL);
	if ((connected_sockfd < 0) && ((errno == EAGAIN) || (errno == EWOULDBLOCK))) {
	    sleep (1);
	}
	else if (connected_sockfd < 0) {
	    fprintf (stderr, "ERROR: c_debug_client_connect: accept () failed\n");
	    return DMI_STATUS_ERR;
	}
	else
	    break;
    }

    // Close the listening socket
    if (close (listen_sockfd) < 0) {
	perror ("ERROR: c_debug_client_connect: error in close (listen_sockfd)");
	return DMI_STATUS_ERR;
    }

    logfile_fp = NULL;                         // No debugging
    // logfile_fp = fopen (logfile_name, "w");    // Debugging
    if (logfile_fp != NULL) {
	fprintf (stdout, "    Logfile for debug client transactions is '%s'\n", logfile_name);
	fprintf (logfile_fp, "CONNECTED on TCP port %0d\n", tcp_port);
    }
    else
	fprintf (stdout, "    Unable to open logfile for debug client transactions: '%s'\n",
		 logfile_name);

    return DMI_STATUS_OK;
}

// ================================================================
// Disconnect from debug client as server.
// Return fail/ok.

uint8_t c_debug_client_disconnect (uint8_t dummy)
{
    uint8_t buf [128];
    ssize_t n;

    fprintf (stdout, "Disconnected from remote debug client on port %0d\n", port);

    shutdown (connected_sockfd, SHUT_WR);

    // Drain remaining bytes arriving
    while (1) {
	n = recv (connected_sockfd, buf, 128, 0);
	if (n == 0)
	    break;
	if ((n == -1) && (errno != EINTR))
	    break;
    }

    if (close (connected_sockfd) < 0) {
	perror ("ERROR: c_debug_client_disconnect:");
	fprintf (stderr, "    socket file descriptor: %0d\n", connected_sockfd);
	return DMI_STATUS_ERR;
    }

    if (logfile_fp != NULL) {
	fprintf (logfile_fp, "DISCONNECTED on port %0d\n", port);
	fclose (logfile_fp);
    }

    return DMI_STATUS_OK;
}

// ================================================================
// Receive 7-byte request from remote client
// Result is:    { status, data_b3, data_b2, data_b1, data_b0, addr_b1, addr_b0, op }

static int command_num = 0;

uint64_t c_debug_client_request_recv (uint8_t dummy)
{
    uint64_t  result   = 0;
    uint8_t  *p_result = (uint8_t *) & result;

    // ----------------
    // First, poll to check if any data is available
    int fd = connected_sockfd;

    struct pollfd  x_pollfd;
    x_pollfd.fd      = fd;
    x_pollfd.events  = POLLRDNORM;
    x_pollfd.revents = 0;

    int n = poll (& x_pollfd, 1, 0);

    if (n < 0) {
	perror ("ERROR: c_debug_client_request_recv (): poll () failed");
	p_result [7] = DMI_STATUS_ERR;
	return result;
    }

    if ((x_pollfd.revents & POLLRDNORM) == 0) {
	// No byte available
	// sched_yield ();    // Allow other threads to run.
	p_result [7] = DMI_STATUS_UNAVAIL;
	return result;
    }

    // ----------------
    // Data is available; read the 7-byte request

    int  data_size = 7;
    int  n_recd    = 0;
    int  n_iters   = 0;
    p_result [0] = DMI_STATUS_ERR;
    while (n_recd < data_size) {
	int n = read (fd, p_result + n_recd, (data_size - n_recd));
	if ((n < 0) && (errno != EAGAIN) && (errno != EWOULDBLOCK)) {
	    if (logfile_fp != NULL) {
		fprintf (logfile_fp, "ERROR: c_debug_client_request_recv () failed\n");
		fprintf (logfile_fp, "    Received %0d bytes so far (of %0d)\n", n_recd, data_size);
		fprintf (logfile_fp, "    Data so far: 0x%0" PRIx64 "\n", result);
		fprintf (logfile_fp, "    read (sock, ...) => %0d\n", n);
	    }
	    p_result [7] = DMI_STATUS_ERR;
	    return result;
	}
	else if (n > 0) {
	    n_recd += n;
	}

	n_iters++;
	if ((n_iters > 0) && ((n_iters % 1000000) == 0)) {
	    if (logfile_fp != NULL) {
		fprintf (logfile_fp, "WARNING: c_debug_client_request_recv () stalled?\n");
		fprintf (logfile_fp, "    Received %0d bytes so far (of %0d)\n", n_recd, data_size);
		fprintf (logfile_fp, "    Data so far: 0x%0" PRIx64 "\n", result);
		fprintf (logfile_fp, "    %0d iterations so far\n", n_iters);
	    }
	}
    }
    p_result [7] = DMI_STATUS_OK;

    if (logfile_fp != NULL) {
	uint8_t  op   = (result         & 0xFF);
	uint16_t addr = ((result >> 8)  & 0xFFFF);
	uint32_t data = ((result >> 24) & 0xFFFFFFFF);
        switch (op) {

	case DMI_OP_READ: {
	    fprintf (logfile_fp, "C_to_S  READ  0x%04x\n", addr);
	    break;
	}
	case DMI_OP_WRITE: {
	    fprintf (logfile_fp, "C_to_S  WRITE  0x%04x  0x%08x\n", addr, data);
	    break;
	}
	case DMI_OP_SHUTDOWN: {
	    fprintf (logfile_fp, "C_to_S  SHUTDOWN\n");
	    break;
	}
	case DMI_OP_START_COMMAND: {
	    fprintf (logfile_fp, "C_to_S  ======== START_COMMAND %0d\n", command_num);
	    command_num++;
	    break;
	}
	default: {
	    fprintf (logfile_fp, "C_to_S ERROR: Unrecognized op %0d; ignored\n", op);

	    fprintf (stderr,
		     "ERROR: c_debug_client_request_recv: Unrecognized op %0d; ignored\n",
		     op);
	}
	}
	fflush (logfile_fp);
    }

    return  result;
}

// ================================================================
// Send 4-byte response 'data' to debug client.
// Returns fail/ok status

uint8_t c_debug_client_response_send (const uint32_t data)
{
    int      fd = connected_sockfd;
    int      data_size = 4;    // 4 bytes
    int      n_sent    = 0;
    int      n_iters   = 0;
    uint8_t *p_data    = (uint8_t *) & data;

    while (n_sent < data_size) {
	int n = write (fd, p_data + n_sent, (data_size - n_sent));
	if ((n < 0) && (errno != EAGAIN) && (errno != EWOULDBLOCK)) {
	    if (logfile_fp != NULL) {
		fprintf (logfile_fp, "ERROR: c_debug_client_response_send (0x%08x) failed\n", data);
		fprintf (logfile_fp, "    Sent %0d bytes so far (of %0d)\n", n_sent, data_size);
		fprintf (logfile_fp, "    write (sock, ...) => %0d\n", n);
	    }
	    return DMI_STATUS_ERR;
	}
	else if (n > 0) {
	    n_sent += n;
	}

	n_iters++;
	if ((n_iters > 0) && ((n_iters % 0x1000000) == 0)) {
	    if (logfile_fp != NULL) {
		fprintf (logfile_fp, "WARNING: c_debug_client_response_send (0x%08x) stalled?\n", data);
		fprintf (logfile_fp, "    Sent %0d bytes so far (of %0d)\n", n_sent, data_size);
		fprintf (logfile_fp, "    %0d iterations so far\n", n_iters);
	    }
	}
    }
    fsync (fd);

    if (logfile_fp != NULL) {
	fprintf (logfile_fp, "S_to_C  0x%08x\n", data);
	fflush (logfile_fp);
    }

    return DMI_STATUS_OK;
}