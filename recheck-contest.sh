#!/bin/bash
cd ~/iouring-lab/youki || exit 1
. ~/.cargo/env 2>/dev/null
cargo fmt --all 2>/dev/null
./scripts/build.sh -o . -r -c contest 2>&1 | grep -E "^(warning|error)|error\[|-->" | head
echo "######## patched youki, 7.2.9"
bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/linux-7.2.9 /home/eugene/iouring-lab/e2e/guest-contest.sh | grep -E "io_uring|seccomp_test"
echo "######## upstream youki (no support), 7.2.9 — both must be 'not ok'"
bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/linux-7.2.9 /home/eugene/iouring-lab/e2e/guest-negative.sh | grep -E " : (ok|not ok)"
