#!/bin/bash
# Build liburing with the new test and run it on the host and two VM kernels.
cd ~/iouring-lab/liburing || exit 1
grep -q "task-restrict-exec.c" test/Makefile || sed -i 's/^\ttask-restrict\.c \\$/&\n\ttask-restrict-exec.c \\/' test/Makefile
grep -n "task-restrict" test/Makefile
[ -f config-host.mak ] || ./configure >/dev/null
make -j"$(nproc)" -C src >/dev/null 2>&1 && make -j"$(nproc)" -C test task-restrict-exec.t task-restrict.t 2>&1 | grep -E "warning|error" | head
ls -la test/task-restrict-exec.t || exit 1
cat > /tmp/lt-guest.sh <<'EOF'
cd /home/eugene/iouring-lab/liburing/test
echo "kernel $(uname -r)"
for t in task-restrict-exec.t task-restrict.t; do
  setpriv --reuid=1000 --regid=1000 --clear-groups ./$t; echo "$t exit=$? (0 pass, 1 fail, 77 skip)"
done
EOF
cp /tmp/lt-guest.sh ~/iouring-lab/lt-guest.sh
echo "######## host"; (cd test && ./task-restrict-exec.t; echo "exit=$?")
echo "######## 7.0";   bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/linux-7.0 /home/eugene/iouring-lab/lt-guest.sh | grep -v modules.order
echo "######## 7.2.9"; bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/linux-7.2.9 /home/eugene/iouring-lab/lt-guest.sh
