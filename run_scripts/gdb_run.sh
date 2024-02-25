#!/bin/bash

./start_stub.sh > /dev/null 2>&1 &
STUB_PID=$!

./start_gdb.sh

pkill -P $STUB_PID
pkill -P $$
