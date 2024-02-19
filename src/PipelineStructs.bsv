import Types::*;

typedef struct {
  Instruction inst;
  Addr pc;
  Addr ppc;
  Bool epoch;
} Fetch2Decode deriving(Bits, Eq);

// typedef struct {
//   // DecodedInst dInst;
//   // Addr pc;
//   // Addr ppc;
//   // Bool epoch;
// } Decode2Rest deriving(Bits, Eq);
