#!/bin/bash
# Wire, format, unit-test and build youki with the io_uring module.
cd ~/iouring-lab/youki || exit 1
. ~/.cargo/env 2>/dev/null
python3 ~/iouring-lab/wire-youki.py || exit 1
git checkout -q -B io-uring-restrictions 2>/dev/null
cargo fmt --all
echo "--- unit tests (io_uring module)"
cargo test -p libcontainer --lib io_uring 2>&1 | grep -E "^test |test result|error(\[|:)|warning: unused" | head -30
echo "--- release build"
start=$(date +%s)
cargo build --release --bin youki 2>&1 | grep -E "^(warning|error)|Finished" | head -20
echo "build seconds: $(( $(date +%s) - start ))"
ls -la target/release/youki
