#!/bin/bash
cd ~/iouring-lab/probe || exit 1
. ~/.cargo/env 2>/dev/null
cargo build --release 2>&1 | grep -E '^(warning|error)|Finished'
bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/linux-7.2.9 | sed -n '/== 11/,$p'
