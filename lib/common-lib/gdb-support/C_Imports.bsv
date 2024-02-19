// Copyright (c) 2013-2019 Bluespec, Inc.  All Rights Reserved

package C_Imports;

// ================================================================
// These are functions imported into BSV during Bluesim or Verilog simulation.
// See C_Imported_Functions.{h,c} for the corresponding C declarations
// and implementations.

// There are several independent groups of functions below; the
// groups are separated by heavy dividers ('// *******')

// Below, 'dummy' args are not used, and are present only to appease
// some Verilog simulators that are finicky about 0-arg functions.

// ================================================================
// BSV lib imports

import Vector :: *;

// Functions for communication with remote debug client.

// ****************************************************************
// ****************************************************************
// ****************************************************************

// ================================================================
// Commands in requests.

Bit #(16) dmi_default_tcp_port = 30000;

Bit #(8) dmi_status_err     = 0;
Bit #(8) dmi_status_ok      = 1;
Bit #(8) dmi_status_unavail = 2;

Bit #(8) dmi_op_read          = 1;
Bit #(8) dmi_op_write         = 2;
Bit #(8) dmi_op_shutdown      = 3;
Bit #(8) dmi_op_start_command = 4;

// ================================================================
// Connect to debug client as server on tcp_port.
// Return fail/ok.

import "BDPI"
function ActionValue #(Bit #(8))  c_debug_client_connect (Bit #(16)  tcp_port);

// ================================================================
// Disconnect from debug client as server.
// Return fail/ok.

import "BDPI"
function ActionValue #(Bit #(8))  c_debug_client_disconnect (Bit #(8)  dummy);

// ================================================================
// Receive 7-byte request from debug client
// Result is:    { status, data_b3, data_b2, data_b1, data_b0, addr_b1, addr_b0, op }

import "BDPI"
function ActionValue #(Bit #(64))  c_debug_client_request_recv (Bit #(8)  dummy);

// ================================================================
// Send 4-byte response 'data' to debug client.
// Returns fail/ok status

import "BDPI"
function ActionValue #(Bit #(8))  c_debug_client_response_send (Bit #(32) data);

// ****************************************************************
// ****************************************************************
// ****************************************************************

endpackage
