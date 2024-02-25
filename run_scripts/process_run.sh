#!/bin/bash


while getopts p:h: flag
do
    case "${flag}" in
        p) program=${OPTARG};;
        h) echo "program list    [array_sum_1d, array_sum_ij, array_sum_ji]"
           echo "                [hanoi_tower, bubble_sort, fibonacci]";;
    esac
done

if [ -z "$program" ]; then
    echo 'missing -p program_list'
    echo "program list    [array_sum_1d, array_sum_ij, array_sum_ji]"
    echo "                [hanoi_tower, bubble_sort, fibonacci]"
    exit 1
fi

echo $program > .running_program.txt

cd /build/CA_Summer_Project/pb_lab5/src/
rm -f gdb/unix_socket/*
./risc-v -p $program
