import Types::*;
import ProcTypes::*;
import Ehr::*;
import ConfigReg::*;
import Fifo::*;

`ifdef INCLUDE_GDB_CONTROL

import FIFOF:: *;
import SpecialFIFOs :: * ;
import Vector::*;
import PipelineStructs::*;
import ClientServer :: *;

`endif 

typedef enum {Ctr, Mem} InstCntType deriving(Bits, Eq);

/*Exercise 4*/
/* TODO: Replace dummies to implement incMissInstTypeCnt */
typedef enum {Dummy1, Dummy2 /*,  ... */} InstMissCntType deriving(Bits, Eq);

interface CsrFile;
    method Action start(Data id);
    method Bool started;
    method Data rd(CsrIndx idx);
    method Action wr(Maybe#(CsrIndx) idx, Data val);
    method ActionValue#(CpuToHostData) cpuToHost;
    method Action incInstTypeCnt(InstCntType inst);
    method Action incBPMissCnt();
    method Action incMissInstTypeCnt(InstMissCntType inst);

    `ifdef INCLUDE_GDB_CONTROL
    method Action resume;
    method Bool halted;
    method Data rd2(CsrIndx idx);
    method Data readCycle;
    method Action setPc(Addr pc);
    method Action handleHaltRsp;
    method Action processFetchResult(Fetch2Decode fetchResult);

    interface Server#(Bool, Bool) csrf_server;
    `endif
endinterface

(* synthesize *)
module mkCsrFile(CsrFile);
    Reg#(Bool) startReg <- mkConfigReg(False);

	// CSR 
    Reg#(Data) numInsts <- mkConfigReg(0); // csrInstret -- read only
    Reg#(Data) cycles <- mkReg(0); // csrCycle -- read only
	Reg#(Data) coreId <- mkConfigReg(0); // csrMhartid -- read only
    
    Reg#(Data) numMem  <- mkConfigReg(0);
    Reg#(Data) numCtr  <- mkConfigReg(0);
    Reg#(Data) numBPMiss <- mkConfigReg(0);

    Fifo#(2, CpuToHostData) toHostFifo <- mkCFFifo; // csrMtohost -- write only
    Fifo#(2, Tuple3#(CsrIndx, Data, Data)) csrFifo <- mkCFFifo;

    `ifdef INCLUDE_GDB_CONTROL
    Reg#(Data) dcsr <- mkReg(32'hf0000117);
    Reg#(Addr) dpc <- mkReg(32'h0);
    Vector#(16, Reg#(Data)) extras <- replicateM(mkReg(0));

    Fifo#(2, CpuToHostData) toProcFifo <- mkCFFifo; // csrMtohost -- write only
    FIFOF#(Bool) haltRspFifo <- mkBypassFIFOF;
    FIFOF#(Bool) cycleHaltRspFifo <- mkBypassFIFOF;
    FIFOF#(Bool) fetchHaltRspFifo <- mkBypassFIFOF;
    Reg#(Bool) debug_stop <- mkReg(True);



    rule count (startReg && !debug_stop);
        cycles <= cycles + 1;
        $display("\nCycle %d ----------------------------------------------------", cycles);
    endrule

    rule gdbStopEveryCycle(startReg && !debug_stop && dcsr[2] == 1'b1);
        cycleHaltRspFifo.enq(True);
    endrule

    `else
    rule count (startReg);
        cycles <= cycles + 1;
        $display("\nCycle %d ----------------------------------------------------", cycles);
    endrule
    `endif

    method Action start(Data id) if(!startReg);
        startReg <= True;
        cycles <= 0;
		coreId <= id;
    endmethod

    method Bool started;
        return startReg;
    endmethod

    method Data rd(CsrIndx idx);
        return (case(idx)
                    csrCycle: cycles;
                    csrInstret: numInsts;
                    csrMhartid: coreId;
					default: ?;
                endcase);
    endmethod
    
    method Action wr(Maybe#(CsrIndx) csrIdx, Data val);
        if(csrIdx matches tagged Valid .idx) begin
            case (idx)
                csrMtohost: begin

                    $fwrite(stderr, "===========================\n");
                    $fwrite(stderr, "Specific type of executed instructions\n");
                    $fwrite(stderr, "Ctr              : %d\n", numCtr);
                    $fwrite(stderr, "Mem              : %d\n", numMem);
                    $fwrite(stderr, "\nMispredicted       : %d\n", numBPMiss);
                    $fwrite(stderr, "==========================================\n");

                    /*Exercise_4*/
                    /* TODO: Implement below to output the counted values */
                    $fwrite(stderr, "Misprediction detail\n");
                    $fwrite(stderr, "J               : %d / %d\n" /* implement */);
                    $fwrite(stderr, "JR              : %d / %d\n" /* implement */);
                    $fwrite(stderr, "BR              : %d / %d\n" /* implement */);
                    $fwrite(stderr, "==========================================\n");

                    // high 16 bits encodes type, low 16 bits are data
                    Bit#(16) hi = truncateLSB(val);
                    Bit#(16) lo = truncate(val);
                    toHostFifo.enq(CpuToHostData {
                        c2hType: unpack(truncate(hi)),
                        data: lo,
                        data2: numInsts
                    });

                    `ifdef INCLUDE_GDB_CONTROL
                    haltRspFifo.enq(True);
                    `endif
                end
                `ifdef INCLUDE_GDB_CONTROL
                csrDcsr: dcsr <= val;
                `endif
            endcase
        end
        else
            numInsts <= numInsts + 1;
    endmethod


    method Action incInstTypeCnt(InstCntType inst);
      case(inst)
        Ctr : numCtr <= numCtr + 1;
        Mem : numMem <= numMem + 1;
        endcase
    endmethod

    method Action incMissInstTypeCnt(InstMissCntType inst);
        /*Exercise_4*/
        /* TODO: implement incMissInstTypeCnt */

        noAction;
    endmethod

    method Action incBPMissCnt();
      numBPMiss <= numBPMiss + 1;
    endmethod

    method ActionValue#(CpuToHostData) cpuToHost;
        toHostFifo.deq;
        return toHostFifo.first;
    endmethod

    `ifdef INCLUDE_GDB_CONTROL

    method Action resume;
        debug_stop <= False;
    endmethod

    method Bool halted;
        return debug_stop;
    endmethod

    method Data rd2(CsrIndx idx);
        return (case(idx)
                    csrDcsr: dcsr;
                    csrDpc: dpc;
                    default: ?;
                endcase);
    endmethod

    method Data readCycle;
        return cycles;
    endmethod

    method Action setPc(Addr pc);
        dpc <= pc;
    endmethod

    method Action handleHaltRsp if (haltRspFifo.notEmpty || cycleHaltRspFifo.notEmpty || fetchHaltRspFifo.notEmpty);
        if (haltRspFifo.notEmpty)
            haltRspFifo.deq;

        if (cycleHaltRspFifo.notEmpty)
            cycleHaltRspFifo.deq;

        if (fetchHaltRspFifo.notEmpty)
            fetchHaltRspFifo.deq;

        debug_stop <= True;
    endmethod

    method Action processFetchResult(Fetch2Decode fetchResult);
        dpc <= fetchResult.pc;
        if (fetchResult.inst ==  32'h00100073)
            fetchHaltRspFifo.enq(True);
    endmethod
    `endif
endmodule