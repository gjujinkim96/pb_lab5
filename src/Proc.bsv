import Types::*;
import ProcTypes::*;
import CMemTypes::*;
import RFile::*;
import IMemory::*;
import DMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import Fifo::*;
import Ehr::*;
import GetPut::*;

`ifdef INCLUDE_GDB_CONTROL

import Memory_Common :: *;
import CustomReg::*;
import FIFOF        :: *;
import ClientServer :: *;
import Connectable  :: *;
import GetPut_Aux   :: *;

import C_Imports        :: *;
import External_Control :: *;
import DM_CPU_Req_Rsp   :: *;
import ISA_Decls        :: *;

`endif


typedef struct {
  Instruction inst;
  Addr pc;
  Addr ppc;
  Bool epoch;
} Fetch2Decode deriving(Bits, Eq);


(*synthesize*)
module mkProc(Proc);
  Reg#(Addr)    pc  <- mkRegU;
  RFile         rf  <- mkRFile;
  IMemory     iMem  <- mkIMemory;
  DMemory     dMem  <- mkDMemory;
  CsrFile     csrf <- mkCsrFile;

  Reg#(ProcStatus)   stat		<- mkRegU;
  Fifo#(1,ProcStatus) statRedirect <- mkBypassFifo;

  // Control hazard handling Elements
  Reg#(Bool) fEpoch <- mkRegU;
  Reg#(Bool) eEpoch <- mkRegU;

  Fifo#(1, Addr)         execRedirect <- mkBypassFifo;

  Fifo#(2, Fetch2Decode)  f2d <- mkPipelineFifo;

  Bool memReady = iMem.init.done() && dMem.init.done();
  rule test (!memReady);
    let e = tagged InitDone;
    iMem.init.request.put(e);
    dMem.init.request.put(e);
  endrule

  rule doFetch(csrf.started && stat == AOK);
	/* Exercise_2 */
	/*TODO: 
	Remove 1-cycle inefficiency when execRedirect is used. */
   	let inst = iMem.req(pc);
   	let ppc = pc + 4;

    if(execRedirect.notEmpty) begin
      execRedirect.deq;
      pc <= execRedirect.first;
      fEpoch <= !fEpoch;
    end
    else begin
      pc <= ppc;
    end

    let fetchResult = Fetch2Decode{inst:inst, pc:pc, ppc:ppc, epoch:fEpoch};
    f2d.enq(fetchResult); 
    $display("Fetch : from Pc %d , \n", pc);

    `ifdef INCLUDE_GDB_CONTROL

    csrf.processFetchResult(fetchResult.pc, fetchResult.inst);
    
    `endif
  endrule

  rule doRest(csrf.started && stat == AOK);
	/* Exercise_1 */
	/* TODO: 
	Divide the doRest rule into doDecode, doRest rules 
	to implement 3-stage pipelined processor */

    let inst   = f2d.first.inst;
    let pc   = f2d.first.pc;
    let ppc    = f2d.first.ppc;
    let iEpoch = f2d.first.epoch;
    f2d.deq;

    if(iEpoch == eEpoch) begin
      	// Decode 
   	    let dInst = decode(inst);

        // Register Read 
        let rVal1 = isValid(dInst.src1) ? rf.rd1(validValue(dInst.src1)) : ?;
        let rVal2 = isValid(dInst.src2) ? rf.rd2(validValue(dInst.src2)) : ?;
        let csrVal = isValid(dInst.csr) ? csrf.rd(validValue(dInst.csr)) : ?;

    		// Execute         
        let eInst = exec(dInst, rVal1, rVal2, pc, ppc, csrVal);               
        
        if(eInst.mispredict) begin
          eEpoch <= !eEpoch;
          execRedirect.enq(eInst.addr);
          $display("jump! :mispredicted, address %d ", eInst.addr);
        end

      //Memory 
      let iType = eInst.iType;
      case(iType)
        Ld :
        begin
          let d <- dMem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
          eInst.data = d;
        end

        St:
        begin
          let d <- dMem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
        end
        Unsupported :
        begin
          $fwrite(stderr, "ERROR: Executing unsupported instruction\n");
          $finish;
        end
      endcase

      //WriteBack 
      if (isValid(eInst.dst)) begin
          rf.wr(fromMaybe(?, eInst.dst), eInst.data);
      end
      csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);

      
	  /* Exercise_3 */
	  /* TODO:
	  1. count the number of each instruciton type
	    Ctr(Control)   : J, Jr, Br
	    Mem(Memory)    : Ld, St 
	        
	  2. count the number of mispredictions */    



	/* Exercise_4 */
	  /* TODO:
	  1. Implement incInstTypeCnt method in CsrFile.bsv
	        
	  2. count number of mispredictions for each instruction type */    

  end
  endrule

  // Does not fire
  rule upd_Stat(csrf.started);
	$display("Stat update");
  	statRedirect.deq;
    stat <= statRedirect.first;
  endrule

  `ifdef INCLUDE_GDB_CONTROL

  FIFOF#(Bool)  f_host_to_cpu <- mkFIFOF;

  FIFOF#(Bool)  f_run_halt_reqs <- mkFIFOF;
  FIFOF#(Bool)  f_run_halt_resp <- mkFIFOF;

  FIFOF#(CpuToHostData) f_test_compl_resp <-mkFIFOF;

  FIFOF#(DM_CPU_Req#(5, XLEN))  f_gpr_reqs <- mkFIFOF;
  FIFOF#(DM_CPU_Rsp#(XLEN))     f_gpr_resp <- mkFIFOF;

  FIFOF#(DM_CPU_Req#(12, XLEN)) f_csr_reqs <- mkFIFOF;
  FIFOF#(DM_CPU_Rsp#(XLEN))     f_csr_resp <- mkFIFOF;

  FIFOF#(Bit#(13)) f_custom_reg_reqs <- mkFIFOF;
  FIFOF#(DM_CPU_Rsp#(MAX_CUSTOM_REG_SIZE))     f_custom_reg_resp <- mkFIFOF;

  FIFOF#(DM_CPU_Req#(AddrSz, DataSz)) f_mod_f2d_reqs <- mkFIFOF;
  FIFOF#(Bool)     f_mod_f2d_resp <- mkFIFOF;

  Reg#(PROC_State)  rg_state <- mkReg(PROC_WAIT_RESET);

  Reg#(Bit#(32)) run_cycle <- mkReg(0);

  rule rl_reset_start;
    f_host_to_cpu.deq;
    $fwrite(stderr, "=============== Processor Reset Start ===============\n");
    rg_state <= PROC_WAIT_GDB;
  endrule

  rule rl_debug_initial_loop (rg_state == PROC_WAIT_GDB);
    if (f_run_halt_reqs.notEmpty && f_run_halt_reqs.first == False) begin
      f_run_halt_reqs.deq;
      rg_state <= PROC_RUNNING;

      csrf.start(0);
      eEpoch <= False;
      fEpoch <= False;
      stat <= AOK;

      $fwrite(stderr, "GDB Connected\n");
    end
    else begin
      run_cycle <= run_cycle + 1;
      if (run_cycle % 1000000 == 0)
        $fwrite(stderr, "Waiting for GDB Connection.......%d\n", run_cycle / 1000000);
    end
  endrule

  rule test_complete;
    let retV <- csrf.cpuToHost;
    f_test_compl_resp.enq(retV);
  endrule

  rule rl_debug_continue((f_run_halt_reqs.first == True));
    f_run_halt_reqs.deq;
    csrf.resume;
    $fwrite(stderr, "Continuing....\n");
  endrule

  rule rl_step_halt;
    csrf.handleHaltRsp;
    f_run_halt_resp.enq(True);
  endrule
  
  Reg#(Bit#(1)) rg_mod_f2d_stage <- mkReg(0);
  Reg#(Fetch2Decode) rg_mod_f2d_tmp <- mkRegU;

  (* descending_urgency ="rl_mod_f2d_pop_elem, rl_mod_f2d_default" *)
  rule rl_mod_f2d_default(rg_mod_f2d_stage == 0);
    let req <- pop(f_mod_f2d_reqs);
    f_mod_f2d_resp.enq(False);
  endrule

  rule rl_mod_f2d_pop_elem(rg_mod_f2d_stage == 0);
    let req <- pop(f_mod_f2d_reqs);

    if (!req.write) begin
      $fwrite(stderr, "Modifying f2d should not be possible from read request");
      $finish(1);
    end

    let cur = f2d.first;
    if (cur.pc == req.address && cur.inst == 32'h00100073) begin
      cur.inst = req.data;
      f2d.deq;
      rg_mod_f2d_tmp <= cur;
      rg_mod_f2d_stage <= 1; 
    end
    else
      f_mod_f2d_resp.enq(False);
  endrule

  rule rl_mod_f2d_reenq_elem(rg_mod_f2d_stage == 1);
    f2d.enq(rg_mod_f2d_tmp);

    rg_mod_f2d_stage <= 0;
    f_mod_f2d_resp.enq(True);
  endrule

  // ----------------
  // Debug Module GPR read/write
  rule rl_debug_gpr;
    let req <- pop(f_gpr_reqs);
    Bit#(5) regname = req.address;

    let data = ?;
    if (req.write) begin
      rf.wr(regname, req.data);
    end
    else begin
      data = rf.gpr_read(regname);
    end

    let rsp = DM_CPU_Rsp{ok: True, data: data};
    f_gpr_resp.enq(rsp);
  endrule

  // ----------------

  // ----------------
  // Debug Module CSR read/write
  rule rl_debug_csr;
    let req <- pop(f_csr_reqs);
    Bit#(12) csr_addr = req.address;

    let data = ?;
    if (req.write) begin
      if (csr_addr == csrDpc)
        csrf.setPc(req.data);
      else if (csr_addr == csrDcsr)
        csrf.wr(tagged Valid csr_addr, req.data);
      end
    else begin
      data = csrf.rd2(csr_addr);
    end

    let rsp = DM_CPU_Rsp{ok: True, data: data};
    f_csr_resp.enq(rsp);
  endrule

  (* descending_urgency ="rl_debug_read_custom_reg, rl_debug_read_default" *)
  rule rl_debug_read_custom_reg;
    let custom_reg_addr <- pop(f_custom_reg_reqs);
    Bit#(MAX_CUSTOM_REG_SIZE) data = ?;
    
    // Custom Reg Replacment START // DO NOT MODIFY

    // Custom Reg Replacment END // DO NOT MODIFY

    let rsp = DM_CPU_Rsp{ok: True, data: data};
    f_custom_reg_resp.enq(rsp);
  endrule

  rule rl_debug_read_default;
    let custom_reg_addr <- pop(f_custom_reg_reqs);
    let rsp = DM_CPU_Rsp{ok: True, data: 0};
    f_custom_reg_resp.enq(rsp);
  endrule
  
  // iMem, dMem =====================================================
  Fifo#(2, MemReq)		dMemReqQ  <- mkCFFifo;
  Fifo#(2, MemResp)		dMemRespQ <- mkCFFifo;
  Fifo#(2, MemReq)		iMemReqQ  <- mkCFFifo;
  Fifo#(2, MemResp)		iMemRespQ <- mkCFFifo;

  // DM memory rules
  rule dm_dMemory;
    dMemReqQ.deq;
    let r = dMemReqQ.first;
    
    let x <- dMem.req(r);
    dMemRespQ.enq(x);
  endrule

  rule dm_iMemory;
    iMemReqQ.deq;
    let r = iMemReqQ.first;
    let x <- iMem.dm_req(r);
    iMemRespQ.enq(x);
  endrule
  // ---------------


  interface Server dmemory_server = toGPServer(dMemReqQ, dMemRespQ);
  interface Server imemory_server = toGPServer(iMemReqQ, iMemRespQ);

  interface Server hart0_server_run_halt = toGPServer(f_run_halt_reqs, f_run_halt_resp);
  interface Server hart0_gpr_mem_server = toGPServer(f_gpr_reqs, f_gpr_resp);
  interface Server hart0_csr_mem_server = toGPServer(f_csr_reqs, f_csr_resp);
  interface Server hart0_custom_reg_mem_server = toGPServer(f_custom_reg_reqs, f_custom_reg_resp);
  interface Server hart0_mod_f2d_server = toGPServer(f_mod_f2d_reqs, f_mod_f2d_resp);

  method Action reset_start(Addr startpc);
    f_host_to_cpu.enq(True);
    pc <= startpc;
  endmethod

  method ActionValue#(CpuToHostData) pop_test_compl_resp;
    f_test_compl_resp.deq;
    return f_test_compl_resp.first;
  endmethod
  // ================================================================
  `endif 
  
  interface iMemInit = iMem.init;
  interface dMemInit = dMem.init;

  method ActionValue#(CpuToHostData) cpuToHost;
    let retV <- csrf.cpuToHost;
    return retV;
  endmethod

  method Action hostToCpu(Bit#(32) startpc) if (!csrf.started && memReady);
    csrf.start(0);
    eEpoch <= False;
    fEpoch <= False;
    pc <= startpc;
    stat <= AOK;
  endmethod
endmodule
