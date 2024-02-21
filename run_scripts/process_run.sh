#!/bin/bash

cd /build/CA_Summer_Project/pb_lab5/src/
rm -f gdb/unix_socket/*
./risc-v -p array_sum_1d
