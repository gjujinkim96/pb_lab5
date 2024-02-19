import ProcTypes::*;
import Proc::*;
import Types::*;

`ifdef INCLUDE_GDB_CONTROL
import GetPut       :: *;
import ClientServer :: *;
import Connectable  :: *;
import GetPut_Aux   :: *;

import C_Imports        :: *;
import External_Control :: *;
import SoC              :: *;
`else
import ProcInterface::*;
`endif

typedef enum{Start, Run, Halt} TestState deriving (Bits, Eq);
typedef 300000 MaxCycle;

`ifdef INCLUDE_GDB_CONTROL
Addr startpc = 32'h10000;
`else
Addr startpc = 32'h0000;
`endif

(*synthesize*)
module mkTestBench();
  Reg#(Bit#(32))     cycle  <- mkReg(0);
  Reg#(TestState)    tState <- mkReg(Start);

  `ifdef INCLUDE_GDB_CONTROL
  SoC_IFC moduleInstance <- mkSoC;
  `else
  Proc moduleInstance <- mkProc;

  rule countCycle(tState == Run);
    if (cycle == fromInteger(valueOf((MaxCycle)))) begin
      tState <= Halt;
    end
    else begin
      cycle <= cycle + 1;
    end
  endrule

  rule halt(tState == Halt);
    $fwrite(stderr, "Program Exceeded the maximum cycle %d\n", fromInteger(valueOf(MaxCycle)));
    $finish;
  endrule
  `endif

  rule start(tState == Start);
    moduleInstance.hostToCpu(startpc);
    tState <= Run;
  endrule

  rule handleExitCode(tState == Run);
    CpuToHostData cpuToHostData <- moduleInstance.cpuToHost;
    if(cpuToHostData.c2hType == ExitCode)
    begin
      $fwrite(stderr, "==================================\n");

      $fwrite(stderr, "Number of Cycles      : %d\n", cycle);
      $fwrite(stderr, "Executed Instructions : %d\n", cpuToHostData.data2);
      
      if(cpuToHostData.data == 0)
        $fwrite(stderr, "Result                :     PASSED\n");
      else
        $fwrite(stderr, "Result                :     FAILED %d\n", cpuToHostData.data);

      $fwrite(stderr, "==================================\n");
      $finish;
    end
  endrule
endmodule
