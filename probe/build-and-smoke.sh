#!/bin/bash
# Build the probe and run it on the host (WSL) kernel as a smoke test.
cd ~/iouring-lab/probe || exit 1
. ~/.cargo/env 2>/dev/null
cargo build --release 2>&1 | grep -E '^(warning|error)|Finished' | head -20
ls target/release/iou-restrict target/release/iou-check || exit 1
echo "--- host kernel $(uname -r): plain check"
./target/release/iou-check
echo "--- host kernel: try task restrictions (expect EINVAL before 7.0)"
./target/release/iou-restrict --nnp --ops 0 -- ./target/release/iou-check
