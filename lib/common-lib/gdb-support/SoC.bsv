package SoC;
// ================================================================
// library imports
import FIFO::*;
import GetPut        :: *;
import ClientServer  :: *;
import Connectable   :: *;
import GetPut_Aux    :: *;

import External_Control :: *;
import Debug_Module     :: *;
import ProcTypes        :: *;
import Proc          :: *;
import Types::*;

import Memory_Common :: *;
import C_Imports        :: *;


interface SoC_IFC;
  method ActionValue#(CpuToHostData) cpuToHost;
  method Action hostToCpu(Addr startpc);
endinterface

(* synthesize *)
module mkSoC(SoC_IFC);
  FIFO#(Control_Req) cntl_reqs <- mkFIFO;
  
  Proc          proc <- mkProc;
	Debug_Module_IFC  debug_module <- mkDebug_Module;
  DMI dm_dmi = debug_module.dmi;

  mkConnection(debug_module.dmemory_client, proc.dmemory_server);
  mkConnection(debug_module.imemory_client, proc.imemory_server);
    
  mkConnection(debug_module.hart0_client_run_halt, proc.hart0_server_run_halt);
  mkConnection(debug_module.hart0_gpr_mem_client, proc.hart0_gpr_mem_server);
  mkConnection(debug_module.hart0_csr_mem_client, proc.hart0_csr_mem_server);
  mkConnection(debug_module.hart0_custom_reg_mem_client, proc.hart0_custom_reg_mem_server);
  mkConnection(debug_module.hart0_mod_f2d_client, proc.hart0_mod_f2d_server);

  rule rl_debug_client_request_recv;
    Bit #(64) req <- c_debug_client_request_recv ('hAA);
    Bit #(8)  status = req [63:56];
    Bit #(32) data   = req [55:24];
    Bit #(16) addr   = req [23:8];
    Bit #(8)  op     = req [7:0];

    if (status == dmi_status_ok) begin
      let cntl_req = ?;
      if (op == dmi_op_read)
        cntl_req = Control_Req {op: external_control_req_op_read_control_fabric,
                                   arg1: zeroExtend (addr),
                                   arg2: 0};
      else if (op == dmi_op_write)
        cntl_req = Control_Req {op: external_control_req_op_write_control_fabric,
          arg1: zeroExtend (addr),
          arg2: zeroExtend (data)};
      cntl_reqs.enq(cntl_req);
    end
  endrule

  rule rl_handle_control_read_req(cntl_reqs.first.op == external_control_req_op_read_control_fabric);
    let cntl_req = cntl_reqs.first;
    cntl_reqs.deq;

    dm_dmi.read_addr(truncate (cntl_req.arg1));
  endrule

  rule rl_handle_control_write_req(cntl_reqs.first.op == external_control_req_op_write_control_fabric);
    let cntl_req = cntl_reqs.first;
    cntl_reqs.deq;

    dm_dmi.write(truncate(cntl_req.arg1), truncate(cntl_req.arg2));
  endrule

  rule rl_debug_client_response_send;
    let dmiData <- dm_dmi.read_data;
    let status <- c_debug_client_response_send (dmiData);
    if (status == dmi_status_err)
      $finish (1);
  endrule

  method ActionValue#(CpuToHostData) cpuToHost;
    let ret <- proc.pop_test_compl_resp;
    return ret;
  endmethod

  method Action hostToCpu(Addr startpc);
    let dmi_status <- c_debug_client_connect(dmi_default_tcp_port);
    if (dmi_status == dmi_status_ok) begin
      proc.reset_start(startpc);
    end
    else begin
      $display ("ERROR: Top_HW_Side.rl_step0: error opening debug client connection.");
      $display ("    Aborting.");
      $finish (1);
    end
  endmethod
endmodule
// ================================================================
endpackage
