#!/bin/bash
# Inside the guest (root): run youki's contest groups for io_uring, plus
# seccomp as a sanity check that the harness itself works here. Mirrors
# scripts/contest.sh without its git lookup (root can't use the repo here).
Y=/home/eugene/iouring-lab/youki
cd $Y || exit 1
echo "kernel $(uname -r)"
./contest run --runtime $Y/target/release/youki --runtimetest $Y/runtimetest -t io_uring seccomp 2>&1 | grep -v "^$" | tail -25
