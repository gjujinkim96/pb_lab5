// Copyright (c) 2016-2019 Bluespec, Inc.  All Rights Reserved

#pragma once

// ================================================================
// These are functions imported into BSV during Bluesim or Verilog simulation.
// See C_Imports.bsv for the corresponding 'import BDPI' declarations.

// There are several independent groups of functions below; the
// groups are separated by heavy dividers ('// *******')

// Below, 'dummy' args are not used, and are present only to appease
// some Verilog simulators that are finicky about 0-arg functions.

// ================================================================

#ifdef __cplusplus
extern "C" {
#endif

// ****************************************************************
// ****************************************************************
// ****************************************************************

// Functions for communication with remote debug client.

// ================================================================

#define  DMI_OP_READ           1
#define  DMI_OP_WRITE          2
#define  DMI_OP_SHUTDOWN       3
#define  DMI_OP_START_COMMAND  4

#define  DMI_STATUS_ERR      0
#define  DMI_STATUS_OK       1
#define  DMI_STATUS_UNAVAIL  2

extern
uint8_t  c_debug_client_connect (const uint16_t tcp_port);

extern
uint8_t c_debug_client_disconnect (uint8_t dummy);

extern
uint64_t c_debug_client_request_recv (uint8_t dummy);

extern
uint8_t c_debug_client_response_send (const uint32_t data);

// ****************************************************************
// ****************************************************************
// ****************************************************************

#ifdef __cplusplus
}
#endif
