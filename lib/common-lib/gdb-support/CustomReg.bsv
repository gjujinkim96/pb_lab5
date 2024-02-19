package CustomReg;

import PipelineStructs::*;

typedef 640 MAX_CUSTOM_REG_SIZE;
Bit#(10) max_custom_reg_size = 640;

// function Bit#(CANON_SIZE) canonicalize_f2d(Maybe#(Fetch2Decode) data);
//     Bit#(CANON_SIZE) ret = 0;
//     let raw = data.Valid;
//     Bit#(1) valid_bit = (isValid(data)) ? 1 : 0;
//     Bit#(8) valid_byte = zeroExtend(valid_bit);
//     Bit#(1) epoch_bit = (raw.epoch) ? 1 : 0;
//     Bit#(8) epoch_byte = zeroExtend(epoch_bit);
//     return { valid_byte, raw.inst, raw.pc, raw.ppc, epoch_byte };
// endfunction

endpackage