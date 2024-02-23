package Debug_Module;
// ================================================================
// library imports
import Memory         :: *;
import FIFOF          :: *;
import GetPut         :: *;
import ClientServer   :: *;
import SpecialFIFOs   :: *;
import GetPut_Aux     :: *;

import DM_Common      :: *;
import DM_CPU_Req_Rsp :: *;
import ISA_Decls			:: *;

import CMemTypes      :: *;
import Types          :: *;
import Fifo           :: *;
import Memory_Common  :: *;

import CustomReg::*;

export DM_Common :: *;
export Debug_Module_IFC (..);
export mkDebug_Module;
// ================================================================


// ================================================================
// Debug Module Interface
interface Debug_Module_IFC;
	interface DMI dmi;

	interface Client#(MemReq, MemResp) dmemory_client;
	interface Client#(MemReq, MemResp) imemory_client;

	interface Client#(Bool, Bool) hart0_client_run_halt;
	interface Client#(DM_CPU_Req#(5, XLEN), DM_CPU_Rsp#(XLEN)) hart0_gpr_mem_client;
	interface Client#(DM_CPU_Req#(12, XLEN), DM_CPU_Rsp#(XLEN)) hart0_csr_mem_client;
	interface Client#(Bit#(13), DM_CPU_Rsp#(MAX_CUSTOM_REG_SIZE)) hart0_custom_reg_mem_client;
	interface Client#(DM_CPU_Req#(AddrSz, DataSz), Bool) hart0_mod_f2d_client;
endinterface
// ================================================================


// ================================================================
// The Debug Module
(* synthesize *)
module mkDebug_Module(Debug_Module_IFC);
	// Run/Halt Client FIFO
	FIFOF#(Bool) f_hart0_run_halt_reqs <- mkFIFOF;
	FIFOF#(Bool) f_hart0_run_halt_resp <- mkFIFOF;

	// GPR Access FIFO
	FIFOF#(DM_CPU_Req#(5, XLEN)) f_hart0_gpr_reqs <- mkFIFOF;
	FIFOF#(DM_CPU_Rsp#(XLEN))    f_hart0_gpr_resp <- mkFIFOF;

	// Memory Access FIFO
	Fifo#(2, MemReq)		dMemReqQ  <- mkCFFifo;
	Fifo#(2, MemResp)		dMemRespQ <- mkCFFifo;
	Fifo#(2, MemReq)		iMemReqQ  <- mkCFFifo;
	Fifo#(2, MemResp)		iMemRespQ <- mkCFFifo;
	
	// CSR Access FIFO
	FIFOF#(DM_CPU_Req#(12, XLEN)) f_hart0_csr_reqs <- mkFIFOF;
	FIFOF#(DM_CPU_Rsp#(XLEN))     f_hart0_csr_resp <- mkFIFOF;

	// custom reg Access FIFO
	FIFOF#(Bit#(13)) f_hart0_custom_reg_reqs <- mkFIFOF;
	FIFOF#(DM_CPU_Rsp#(MAX_CUSTOM_REG_SIZE))     f_hart0_custom_reg_resp <- mkFIFOF;

	// modify f2d when write mem FIFO
	FIFOF#(DM_CPU_Req#(AddrSz, DataSz)) f_hart0_mod_f2d_reqs <- mkFIFOF;
	FIFOF#(Bool)     f_hart0_mod_f2d_resp <- mkFIFOF;

	// CPU run/halt
	Reg#(Bool) rg_cpu_running <- mkReg(False);
	Reg#(Bool) rg_cpu_halted  <- mkReg(True);
	Reg#(Bool) rg_cpu_ready_to_run  <- mkReg(False);

	// Abstract Command Registers
	Reg#(Bool)	   rg_abstractcs_busy          <- mkRegU;
	Reg#(Bool)     rg_start_reg_access         <- mkReg(False);
	Reg#(Bool)     rg_command_access_reg_write <- mkRegU;
	Reg#(Bit#(13)) rg_command_access_reg_regno <- mkRegU;
	Reg#(DM_Word)  rg_data0										 <- mkRegU;
	Reg#(Bit#(MAX_CUSTOM_REG_SIZE)) rg_custom_reg_data <- mkRegU;
	Reg#(Bit#(7)) rg_custom_reg_idx <- mkRegU;

	// Memory Status
	Reg#(DM_Word)	sbaddress                   <- mkReg(0);
	Reg#(DM_Word)	rg_sbaddress_reading        <- mkReg(0);
	Reg#(SB_State)	rg_sb_state					<- mkReg(SB_NOTBUSY);
	Bool			sbbusy = (rg_sb_state != SB_NOTBUSY);
	Reg#(DM_Word)	rg_sbdata0					<- mkRegU;

	// Memory rg
	Reg #(Bool)        rg_sbcs_sbbusyerror     <- mkRegU;
	Reg #(Bool)        rg_sbcs_sbreadonaddr    <- mkRegU;
	Reg #(DM_sbaccess) rg_sbcs_sbaccess        <- mkRegU;
	Reg #(Bool)        rg_sbcs_sbautoincrement <- mkRegU;
	Reg #(Bool)        rg_sbcs_sbreadondata    <- mkRegU;
	Reg #(DM_sberror)  rg_sbcs_sberror         <- mkRegU;

	UInt #(3)          sbversion = 1;

	DM_Word virt_rg_sbcs = {pack (sbversion),
							6'b0,
							pack (rg_sbcs_sbbusyerror),
							pack (sbbusy),
							pack (rg_sbcs_sbreadonaddr),
							pack (rg_sbcs_sbaccess),
							pack (rg_sbcs_sbautoincrement),
							pack (rg_sbcs_sbreadondata),
							pack (rg_sbcs_sberror),
							7'd32,    // sbasize -- address size
							1'b0,     // sbaccess128
							1'b0,     // sbaccess64
							1'b1,     // sbaccess32
							1'b1,     // sbaccess16
							1'b1};    // sbaccess8

	Bool is_gpr = ((fromInteger(dm_command_access_reg_regno_gpr_0) <= rg_command_access_reg_regno)
		  && (rg_command_access_reg_regno <= fromInteger(dm_command_access_reg_regno_gpr_1F)));
	Bool is_csr = ((fromInteger(dm_command_access_reg_regno_csr_0) <= rg_command_access_reg_regno)
		  && (rg_command_access_reg_regno <= fromInteger(dm_command_access_reg_regno_csr_FFF)));
	Bool is_custom_reg = ((fromInteger(dm_command_access_reg_regno_custom_0) <= rg_command_access_reg_regno)
		  && (rg_command_access_reg_regno <= fromInteger(dm_command_access_reg_regno_custom_100)));
	

	// ================================================================
	// Debug Module Rules
	Reg#(Bool) is_tracking <- mkReg(False);

	rule rl_gpr_start(rg_abstractcs_busy && rg_start_reg_access && is_gpr);
		Bit #(5) gpr_addr = truncate(rg_command_access_reg_regno - fromInteger(dm_command_access_reg_regno_gpr_0));

		let req = DM_CPU_Req{write: rg_command_access_reg_write, address: gpr_addr, data: rg_data0};
		f_hart0_gpr_reqs.enq(req);
		rg_start_reg_access <= False;
	endrule

	rule rl_grp_finish;
		let rsp <- pop(f_hart0_gpr_resp);
		if (!rg_command_access_reg_write)
			rg_data0 <= rsp.data;
		rg_abstractcs_busy <= False;
	endrule

	rule rl_csr_start(rg_abstractcs_busy && rg_start_reg_access && is_csr);
		Bit#(12) csr_addr = truncate(rg_command_access_reg_regno - fromInteger(dm_command_access_reg_regno_csr_0));
		let req = DM_CPU_Req{write: rg_command_access_reg_write, address: csr_addr, data: rg_data0};
		f_hart0_csr_reqs.enq(req);
		rg_start_reg_access <= False;
	endrule

	rule rl_csr_finish;
		let rsp <- pop(f_hart0_csr_resp);
		if (!rg_command_access_reg_write)
			rg_data0 <= rsp.data;
		rg_abstractcs_busy <= False;
	endrule

	rule rl_custom_reg_start(rg_abstractcs_busy && rg_start_reg_access && is_custom_reg);
		Bit#(13) custom_reg_addr = rg_command_access_reg_regno - fromInteger(dm_command_access_reg_regno_custom_0);

		if (rg_command_access_reg_write) begin
			$fwrite(stderr, "Writing to custom reg not supported!");
			$finish(1);
		end

		f_hart0_custom_reg_reqs.enq(custom_reg_addr);
		rg_start_reg_access <= False;
	endrule

	rule rl_custom_reg_finish;
		let rsp <- pop(f_hart0_custom_reg_resp);

		rg_custom_reg_data <= rsp.data;
		rg_custom_reg_idx <= 0;

		rg_abstractcs_busy <= False;
	endrule

	rule rl_sb_finish(rg_sb_state != SB_NOTBUSY);
		let data <- pop(dMemRespQ);
		iMemRespQ.deq;

		if (rg_sb_state == SB_READ_FINISH)
			rg_sbdata0 <= data;
		else if (rg_sb_state == SB_WRITE_FINISH)
			f_hart0_mod_f2d_resp.deq;	

		rg_sb_state <= SB_NOTBUSY;
	endrule

	rule rl_proc_halt_resp;
		let rsp <- pop(f_hart0_run_halt_resp);
		if (rsp) begin
			rg_cpu_running <= rg_cpu_halted;
			rg_cpu_halted  <= rg_cpu_running;
		end
	endrule
	// ================================================================
	// Functions for memory access
	function Integer fn_sbaccess_to_addr_incr (DM_sbaccess sbaccess);
		case (sbaccess)
			DM_SBACCESS_8_BIT:   return 1;
			DM_SBACCESS_16_BIT:  return 2;
			DM_SBACCESS_32_BIT:  return 4;
			DM_SBACCESS_64_BIT:  return 8;
			DM_SBACCESS_128_BIT: return 16;
		endcase
	endfunction

	Integer addr_incr = fn_sbaccess_to_addr_incr (rg_sbcs_sbaccess);

	function Action fa_sbaddress_incr (Bit #(64) addr64);
		action
			Bit #(64) next_sbaddress = addr64 + fromInteger (addr_incr);
			sbaddress <= next_sbaddress [31:0];
		endaction
	endfunction

	function Action fa_fabric_send_read_req (Bit #(64) addr64);
		action
			Addr fabric_addr = truncate (addr64);
			let r = MemReq{op:Ld,addr:fabric_addr,data:?};
			iMemReqQ.enq(r);
			dMemReqQ.enq(r);

			// Save read-address for byte-lane extraction from later response
			// (since rg_sbaddress may be incremented by then).
			rg_sbaddress_reading <= fabric_addr;
			rg_sb_state <= SB_READ_FINISH;
		endaction
	endfunction

	function Action fa_fabric_send_write_req (Bit #(64) data64);
		action
			Addr fabric_addr = truncate(sbaddress);
			Data fabric_data = truncate(data64);
			let r = MemReq{op:St,addr:fabric_addr,data:fabric_data};
			iMemReqQ.enq(r);
			dMemReqQ.enq(r);
			rg_sb_state <= SB_WRITE_FINISH;

			let req = DM_CPU_Req{write: True, address: fabric_addr, data: fabric_data};
			f_hart0_mod_f2d_reqs.enq(req);
		endaction
	endfunction

	function Action fa_rg_sbcs_write (DM_Word  dm_word);
		action
		Bool        sbbusyerror     = unpack (dm_word [22]);
		Bool        sbreadonaddr    = unpack (dm_word [20]);
		DM_sbaccess sbaccess        = unpack (dm_word [19:17]);
		Bool        sbautoincrement = unpack (dm_word [16]);
		Bool        sbreadondata    = unpack (dm_word [15]);
		DM_sberror  sberror         = unpack (dm_word [14:12]);

		// No-op if not clearing existing sberror
		if ((rg_sbcs_sberror != DM_SBERROR_NONE) && (sberror == DM_SBERROR_NONE)) begin
			// Existing error is not being cleared
		end

		// No-op if not clearing existing sbbusyerror
		else if (rg_sbcs_sbbusyerror && (! sbbusyerror)) begin
		end

		// Check that requested access size is supported
		else if (   (sbaccess == DM_SBACCESS_128_BIT) || (sbaccess == DM_SBACCESS_64_BIT)) begin
			rg_sbcs_sberror <= DM_SBERROR_OTHER;
		end

		// Ok
		else begin
			rg_sbcs_sbbusyerror     <= False;
			rg_sbcs_sbreadonaddr    <= sbreadonaddr;
			rg_sbcs_sbaccess        <= sbaccess;
			rg_sbcs_sbautoincrement <= sbautoincrement;
			rg_sbcs_sbreadondata    <= sbreadondata;
			rg_sbcs_sberror         <= DM_SBERROR_NONE;
		end
	endaction
	endfunction

	function Action fa_rg_sbaddress_write (DM_Addr dm_addr, DM_Word dm_word);
		action
		if (sbbusy) begin
			rg_sbcs_sbbusyerror <= True;
		end

		else if (rg_sbcs_sbbusyerror) begin
		end

		else if (rg_sbcs_sberror != DM_SBERROR_NONE) begin
		end

		else if (dm_addr == dm_addr_sbaddress0) begin
			Bit #(64) addr64 = { sbaddress, dm_word };
			if (rg_sbcs_sbreadonaddr) begin
				fa_fabric_send_read_req  (addr64);
				if (rg_sbcs_sbautoincrement)
					fa_sbaddress_incr (addr64);
				else
					sbaddress <= dm_word;
			end else
				sbaddress <= dm_word;
		end
		endaction
	endfunction

	function ActionValue #(DM_Word) fav_rg_sbdata_read (DM_Addr dm_addr);
		actionvalue
		DM_Word result = 0;
		if (sbbusy) begin
			rg_sbcs_sbbusyerror <= True;
		end

		else if (rg_sbcs_sbbusyerror) begin
		end

		else if (rg_sbcs_sberror != DM_SBERROR_NONE) begin
		end

		else if (dm_addr == dm_addr_sbdata0) begin
			result = rg_sbdata0;
			// Increment sbaddress if needed
			if (rg_sbcs_sbautoincrement) begin
					fa_sbaddress_incr ({0,sbaddress});
			end

			// Auto-read next data if needed
			if (rg_sbcs_sbreadondata && (dm_addr == dm_addr_sbdata0)) begin
					fa_fabric_send_read_req ({0,sbaddress});
			end
		end
		return result;
		endactionvalue
	endfunction

	function Action fa_rg_sbdata_write (DM_Addr dm_addr, DM_Word dm_word);
		action
		if (sbbusy) begin
			rg_sbcs_sbbusyerror <= True;
		end

		else if (rg_sbcs_sbbusyerror) begin
		end

		else if (rg_sbcs_sberror != DM_SBERROR_NONE) begin
		end

		else if (dm_addr == dm_addr_sbdata0) begin
			rg_sbdata0 <= dm_word;
			fa_fabric_send_write_req (zeroExtend (dm_word));

			if (rg_sbcs_sbautoincrement) begin
				fa_sbaddress_incr ({0,sbaddress});
			end
		end
		endaction
   endfunction

	function ActionValue #(DM_Word) fav_rg_custom_reg_read (DM_Addr dm_addr);
		actionvalue
		DM_Word result = 0;
		if (dm_addr == dm_addr_custom_reg) begin
			let upper = max_custom_reg_size - 1 - rg_custom_reg_idx;
			let lower = upper - 32 + 1;
	
			result = rg_custom_reg_data[upper:lower];
			rg_custom_reg_idx <= rg_custom_reg_idx + 32;
		end
		return result;
		endactionvalue
	endfunction

	// ================================================================
	// Debug Module Interface

	FIFOF#(DM_Addr) f_read_addr <-mkBypassFIFOF;
	interface DMI dmi;
		method Action read_addr(DM_Addr dm_addr);
			f_read_addr.enq(dm_addr);
		endmethod

		method ActionValue#(DM_Word) read_data;
			let dm_addr = f_read_addr.first;
			f_read_addr.deq;
			DM_Word dm_word = ?;
			
			if      (dm_addr == dm_addr_dmstatus) begin
				if (rg_cpu_ready_to_run) begin
					rg_cpu_ready_to_run <= False;
					f_hart0_run_halt_reqs.enq(True);
				end
				dm_word = {14'b0, 6'b110000, pack(rg_cpu_running), pack(rg_cpu_running), pack(rg_cpu_halted), pack(rg_cpu_halted), 8'b10000010};
			end
			else if (dm_addr == dm_addr_abstractcs)
				dm_word = {19'b0, pack(rg_abstractcs_busy), 12'b1};
			else if (dm_addr == dm_addr_data0)
				dm_word = rg_data0;
			else if (dm_addr == dm_addr_sbcs)
				dm_word = virt_rg_sbcs;
			else if (dm_addr == dm_addr_sbaddress0)
				dm_word = sbaddress;
			else if (dm_addr == dm_addr_sbdata0)
				dm_word <- fav_rg_sbdata_read(dm_addr);
			else if (dm_addr == dm_addr_custom_reg)
				dm_word <- fav_rg_custom_reg_read(dm_addr);
			return dm_word;
		endmethod

		method Action write(DM_Addr dm_addr, DM_Word dm_word);
			if (dm_addr == dm_addr_dmcontrol) begin
				let haltreq   = fn_dmcontrol_haltreq(dm_word);
				let resumereq = fn_dmcontrol_resumereq(dm_word);
				
				if (haltreq) begin
					f_hart0_run_halt_reqs.enq(False);
				end
				else if (resumereq) begin
					rg_cpu_running <= rg_cpu_halted;
					rg_cpu_halted  <= rg_cpu_running;
					rg_cpu_ready_to_run <= True;
				end
			end
			else if (dm_addr == dm_addr_command) begin
				Bool  is_write = fn_command_access_reg_write(dm_word);
				Bit#(13) regno = truncate (fn_command_access_reg_regno(dm_word));
				rg_command_access_reg_write <= is_write;
				rg_command_access_reg_regno <= regno;
				rg_abstractcs_busy <= True;
				rg_start_reg_access <= True;
			end
			else if (dm_addr == dm_addr_data0) begin
				rg_data0 <= dm_word;
			end
			else if (dm_addr == dm_addr_sbcs) begin
				fa_rg_sbcs_write(dm_word);
			end
			else if (dm_addr == dm_addr_sbaddress0) begin
				fa_rg_sbaddress_write(dm_addr, dm_word);
			end
			else if (dm_addr == dm_addr_sbdata0) begin
				fa_rg_sbdata_write(dm_addr, dm_word);
			end
		endmethod
	endinterface
	// ================================================================

	interface Client dmemory_client = toGPClient(dMemReqQ, dMemRespQ);
	interface Client imemory_client = toGPClient(iMemReqQ, iMemRespQ);

	interface Client hart0_client_run_halt = toGPClient(f_hart0_run_halt_reqs, f_hart0_run_halt_resp);
	interface Client hart0_gpr_mem_client = toGPClient(f_hart0_gpr_reqs, f_hart0_gpr_resp);

	interface Client hart0_csr_mem_client = toGPClient(f_hart0_csr_reqs, f_hart0_csr_resp);
	interface Client hart0_custom_reg_mem_client = toGPClient(f_hart0_custom_reg_reqs, f_hart0_custom_reg_resp);
	interface Client hart0_mod_f2d_client = toGPClient(f_hart0_mod_f2d_reqs, f_hart0_mod_f2d_resp);
endmodule
// ================================================================
endpackage
