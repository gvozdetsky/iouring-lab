#!/bin/bash
# Final checks for the liburing docs PR: every test still builds with the
# synced header, and the BPF/restriction tests pass on 7.2.9 (IPv6 on).
L=~/iouring-lab/liburing
cd $L || exit 1
git log --oneline -2
make -C src -j"$(nproc)" >/dev/null 2>&1 || { echo "src build failed"; exit 1; }
make -C test -j"$(nproc)" >/tmp/test-build.log 2>&1 && echo "all tests build" || { echo "test build FAILED"; grep -E "error" /tmp/test-build.log | head; exit 1; }
grep -c "warning:" /tmp/test-build.log | sed 's/^/compiler warnings: /'
cd ~/iouring-lab/docs-check && cc -Wall -O2 -o docs-check docs-check.c -I$L/src/include $L/src/liburing.a || exit 1
cat > guest-final.sh <<'EOF'
echo "kernel $(uname -r)"
cd /home/eugene/iouring-lab/liburing/test
for t in cbpf_filter.t task-restrict.t task-restrict-exec.t; do
  ./$t > /tmp/$t.root 2>&1; r=$?
  setpriv --reuid=1000 --regid=1000 --clear-groups ./$t > /tmp/$t.user 2>&1; u=$?
  echo "$t: root exit=$r, uid1000 exit=$u"
  [ $r -ne 0 ] && grep -i -m3 "fail" /tmp/$t.root
done
setpriv --reuid=1000 --regid=1000 --clear-groups /home/eugene/iouring-lab/docs-check/docs-check
EOF
bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/linux-7.2.9 ~/iouring-lab/docs-check/guest-final.sh | grep -v '^$'
