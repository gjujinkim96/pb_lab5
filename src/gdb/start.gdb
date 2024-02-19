set tdesc filename /build/CA_Summer_Project/pb_lab5/src/gdb/custom.xml
set architecture riscv:rv32
file /build/CA_Summer_Project/lab4/gdbstub/Run/elfs/array_sum_1d

target remote :31000
# tui new-layout asmregs {-horizontal asm 1 regs 1} 2 status 0 cmd 1
tui new-layout asmregs {-horizontal asm 2 {status 0 cmd 1} 3} 2   regs 1
layout asmregs
tui reg pipe

load /build/CA_Summer_Project/lab4/gdbstub/Run/elfs/array_sum_1d
