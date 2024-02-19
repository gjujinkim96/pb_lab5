package Memory_Common;

import CMemTypes :: *;
import Types     :: *;

interface Memory_Server_IFC;
	method Action dMemoryRequest(MemReq r);
	method ActionValue#(MemResp) dMemoryResponse;
	method Action iMemoryRequest(MemReq r);
	method ActionValue#(MemResp) iMemoryResponse;
endinterface

interface Memory_Client_IFC;
	method ActionValue#(MemReq) dMemoryRequest;
	method Action dMemoryResponse(MemResp r);
	method ActionValue#(MemReq) iMemoryRequest;
	method Action iMemoryResponse(MemResp r);
endinterface

typedef enum {
	SB_NOTBUSY,
	SB_READ_FINISH,
	SB_WRITE_FINISH
} SB_State deriving (Bits, Eq, FShow);

typedef enum {
	DM_SBACCESS_8_BIT,
	DM_SBACCESS_16_BIT,
	DM_SBACCESS_32_BIT,
	DM_SBACCESS_64_BIT,
	DM_SBACCESS_128_BIT
} DM_sbaccess deriving (Bits, Eq, FShow);

typedef enum {
	DM_SBERROR_NONE,          // 0
	DM_SBERROR_TIMEOUT,       // 1
	DM_SBERROR_BADADDR,       // 2
	DM_SBERROR_OTHER,         // 3
	DM_SBERROR_BUSY_STALE,    // 4
	DM__SBERROR_UNDEF5,        // 5
	DM_SBERROR_UNDEF6,        // 6
	DM_SBERROR_UNDEF7_W1C     // 7, used in writes, to clear sberror
} DM_sberror deriving (Bits, Eq, FShow);


endpackage
