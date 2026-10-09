#!/bin/bash
# Is the cbpf_filter.t failure caused by the header sync? Build it with the
# original header and with the synced one, run both as root and as uid 1000.
L=~/iouring-lab/liburing
D=~/iouring-lab/docs-check
cd $L || exit 1
build() {  # $1 = label
  make -C src -j"$(nproc)" >/dev/null 2>&1
  rm -f test/cbpf_filter.t && make -C test -j"$(nproc)" cbpf_filter.t >/dev/null 2>&1
  cp test/cbpf_filter.t $D/cbpf_filter.$1.t
}
git stash -q && build orig && git stash pop -q && build synced
git diff --stat
cd $D && cc -Wall -O2 -o docs-check docs-check.c -I$L/src/include $L/src/liburing.a || exit 1
cat > guest-baseline.sh <<'EOF'
D=/home/eugene/iouring-lab/docs-check
echo "kernel $(uname -r)"
cd /home/eugene/iouring-lab/liburing/test
for v in orig synced; do
  $D/cbpf_filter.$v.t > /tmp/root.$v 2>&1; r=$?
  setpriv --reuid=1000 --regid=1000 --clear-groups $D/cbpf_filter.$v.t > /tmp/user.$v 2>&1; u=$?
  echo "cbpf_filter ($v header): root exit=$r, uid1000 exit=$u"
done
echo "--- first failures, synced header, uid 1000:"; grep -i -m5 "fail\|error\|expected" /tmp/user.synced
echo "--- first failures, synced header, root:"; grep -i -m5 "fail\|error\|expected" /tmp/root.synced
setpriv --reuid=1000 --regid=1000 --clear-groups $D/docs-check | grep "^ *3\.\|then task"
EOF
for k in linux-7.0 linux-7.2.9; do
  bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/$k $D/guest-baseline.sh | grep -v -e modules.order -e '^$'
done
