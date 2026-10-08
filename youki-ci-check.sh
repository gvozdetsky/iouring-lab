#!/bin/bash
cd ~/iouring-lab/youki || exit 1
. ~/.cargo/env 2>/dev/null
git fetch -q https://github.com/youki-dev/youki.git main
git -c user.name="Eugene Gvozdetsky" -c user.email="gvozdet@gmail.com" rebase -q FETCH_HEAD || { git rebase --abort; echo "REBASE FAILED"; exit 1; }
git log --oneline -4
grep -n "lint\|clippy" justfile | head -5
echo "--- fmt"; cargo fmt --all -- --check >/dev/null 2>&1 && echo "fmt ok" || cargo fmt --all -- --check 2>&1 | grep -v "^Warning: can't set" | head -20
echo "--- clippy"; cargo clippy -q --all-targets -p libcontainer -p contest -p runtimetest -- -D warnings 2>&1 | grep -E "^(warning|error)|-->" | head -30; echo "clippy exit=${PIPESTATUS[0]}"
echo "--- unit tests"; cargo test -q -p libcontainer --lib io_uring 2>&1 | grep -E "test result|FAILED|panicked"
