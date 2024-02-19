import Types::*;
import CMemTypes::*;
import RegFile::*;
import MemInit::*;

interface IMemory;
    method Instruction req(Addr a);
    interface MemInitIfc init;

    `ifdef INCLUDE_GDB_CONTROL
    method ActionValue#(MemResp) dm_req(MemReq r);
    `endif
endinterface

(* synthesize *)
module mkIMemory(IMemory);
	// In simulation we always init memory from a fixed VMH file (for speed)
	RegFile#(Bit#(16), Data) mem <- mkRegFileFullLoad("memory.vmh");
	MemInitIfc memInit <- mkDummyMemInit;
   // RegFile#(Bit#(16), Data) mem <- mkRegFileFull();
   // MemInitIfc memInit <- mkMemInitRegFile(mem);

    method Instruction req(Addr a); //if (memInit.done());
        return mem.sub(truncate(a>>2));
    endmethod

    interface MemInitIfc init = memInit;

    `ifdef INCLUDE_GDB_CONTROL
    method ActionValue#(MemResp) dm_req(MemReq r); //if (memInit.done());
        Bit#(16) index = truncate(r.addr>>2);
        let data = mem.sub(index);
        if(r.op==St) begin
            mem.upd(index, r.data);
        end
        return data;
    endmethod
    `endif
endmodule

