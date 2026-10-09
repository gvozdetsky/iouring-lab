#!/bin/bash
# Sync liburing's bpf_filter.h with the 7.2.9 uapi header, build docs-check
# against that liburing and run it on 7.0 and 7.2.9.
L=~/iouring-lab/liburing
cp ~/iouring-lab/linux-7.2.9/include/uapi/linux/io_uring/bpf_filter.h $L/src/include/liburing/io_uring/bpf_filter.h
git -C $L diff --stat
make -C $L/src -j"$(nproc)" >/dev/null 2>&1 || { echo "liburing build failed"; exit 1; }
make -C $L/test -j"$(nproc)" cbpf_filter.t task-restrict.t task-restrict-exec.t 2>&1 | grep -E "warning|error" | head
cd ~/iouring-lab/docs-check
cc -Wall -O2 -o docs-check docs-check.c -I$L/src/include $L/src/liburing.a || exit 1
cat > guest.sh <<'EOF'
echo "kernel $(uname -r)"
setpriv --reuid=1000 --regid=1000 --clear-groups /home/eugene/iouring-lab/docs-check/docs-check
cd /home/eugene/iouring-lab/liburing/test
for t in cbpf_filter.t task-restrict.t task-restrict-exec.t; do
  setpriv --reuid=1000 --regid=1000 --clear-groups ./$t >/dev/null 2>&1; echo "$t exit=$?"
done
EOF
for k in linux-7.0 linux-7.2.9; do
  bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/$k /home/eugene/iouring-lab/docs-check/guest.sh | grep -v -e modules.order -e '^$'
done
