import Types::*;
import FShow::*;
import CMemTypes::*;
import ProcTypes::*;

`ifdef INCLUDE_GDB_CONTROL

import ClientServer  :: *;
import ISA_Decls::*;
import CustomReg::*;
import DM_CPU_Req_Rsp::*;
import Memory_Common::*;

interface Proc;
  interface Server#(MemReq, MemResp) dmemory_server;
  interface Server#(MemReq, MemResp) imemory_server;

  interface Server#(Bool, Bool) hart0_server_reset;
  interface Server#(Bool, Bool) hart0_server_run_halt;
  interface Server#(DM_CPU_Req#(5, XLEN), DM_CPU_Rsp#(XLEN)) hart0_gpr_mem_server;
  interface Server#(DM_CPU_Req#(12, XLEN), DM_CPU_Rsp#(XLEN)) hart0_csr_mem_server;
  interface Server#(Bit#(13), DM_CPU_Rsp#(MAX_CUSTOM_REG_SIZE)) hart0_custom_reg_mem_server;
  interface Server#(DM_CPU_Req#(AddrSz, DataSz), Bool) hart0_mod_f2d_server;

  method Action reset_start(Addr startpc);
  method ActionValue#(CpuToHostData) pop_test_compl_resp;
endinterface

`else

interface Proc;
    method ActionValue#(CpuToHostData) cpuToHost;
    method Action hostToCpu(Addr startpc);

    interface MemInitIfc iMemInit;
    interface MemInitIfc dMemInit;
endinterface

`endif