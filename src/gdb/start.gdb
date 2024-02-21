set tdesc filename custom.xml
set architecture riscv:rv32
file /build/CA_Summer_Project/gdbstub/Run/elfs/array_sum_1d

target remote unix_socket/stub_gdb_31000
# tui new-layout asmregs {-horizontal asm 1 regs 1} 2 status 0 cmd 1
tui new-layout asmregs {-horizontal asm 2 {status 0 cmd 1} 3} 2   regs 1
layout asmregs
tui reg pipe

load /build/CA_Summer_Project/gdbstub/Run/elfs/array_sum_1d
