#!/bin/bash
cd ~/iouring-lab/youki || exit 1
. ~/.cargo/env 2>/dev/null
python3 ~/iouring-lab/wire-contest.py || exit 1
cargo fmt --all 2>/dev/null
grep -n "test-contest" -A8 justfile | head -14
grep -n "is_runtime_youki" tests/contest/contest/src/utils/mod.rs
start=$(date +%s)
./scripts/build.sh -o . -r -c contest 2>&1 | grep -E "^(warning|error)|error\[|Finished|-->" | head -30
echo "build seconds: $(( $(date +%s) - start ))"
ls -la contest runtimetest youki 2>&1
file runtimetest | cut -c1-120
