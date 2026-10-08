#!/bin/bash
# Build upstream youki (no io_uring support) and run the new contest group
# against it: io_uring_policy must fail, proving the test detects a runtime
# that ignores the policy.
cd ~/iouring-lab/youki || exit 1
. ~/.cargo/env 2>/dev/null
[ -d ../youki-main ] || git worktree add -q ../youki-main 6616d310
cd ../youki-main && cargo build -q --release --bin youki 2>&1 | grep -E "^error" | head
ls -la target/release/youki || exit 1
cat > ~/iouring-lab/e2e/guest-negative.sh <<'EOF'
Y=/home/eugene/iouring-lab/youki
cd $Y && ./contest run --runtime /home/eugene/iouring-lab/youki-main/target/release/youki --runtimetest $Y/runtimetest -t io_uring 2>&1 | grep -v "^$" | tail -12
EOF
bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/linux-7.2.9 /home/eugene/iouring-lab/e2e/guest-negative.sh
