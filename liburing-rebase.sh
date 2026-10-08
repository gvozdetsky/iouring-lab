#!/bin/bash
# Rebase the signed test commit on current liburing master, rebuild, retest.
cd ~/iouring-lab/liburing || exit 1
git fetch -q origin master
git -c user.name="Eugene Gvozdetsky" -c user.email="gvozdet@gmail.com" rebase -q origin/master || { git rebase --abort; echo "REBASE FAILED"; exit 1; }
git log --oneline -2
git log -1 --format='%b' | grep -E "Signed-off-by|Assisted-by"
make -j"$(nproc)" -C src >/dev/null 2>&1 || { echo "src build failed"; exit 1; }
rm -f test/task-restrict-exec.t
make -j"$(nproc)" -C test task-restrict-exec.t task-restrict.t 2>&1 | grep -E "warning|error" | head
echo "######## host";  (cd test && ./task-restrict-exec.t; echo "exit=$?")
echo "######## 7.0";   bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/linux-7.0 /home/eugene/iouring-lab/lt-guest.sh | grep -v -e modules.order -e '^$'
echo "######## 7.2.9"; bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/linux-7.2.9 /home/eugene/iouring-lab/lt-guest.sh | grep -v '^$'
