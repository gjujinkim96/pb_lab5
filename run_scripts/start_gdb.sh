#!/bin/bash

if ! [ -f .running_program.txt ]; then
  echo "run process_run.sh first!"
  exit 1
fi

program=$(cat .running_program.txt)

cd /build/CA_Summer_Project/pb_lab5/src/gdb

rm -f start.gdb

sed -e "s/{SED_PROGRAM}/$program/g" base_start.gdb > start.gdb

riscv64-unknown-elf-gdb -x start.gdb
