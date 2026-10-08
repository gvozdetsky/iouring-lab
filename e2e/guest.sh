#!/bin/bash
# Runs inside the virtme-ng guest as root: start each bundle with youki.
L=/home/eugene/iouring-lab
Y=$L/youki/target/release/youki
STATE=/tmp/youki-state
mkdir -p $STATE
echo "== guest kernel $(uname -r); cgroup: $(stat -fc %T /sys/fs/cgroup)"
for name in none deny-default allow-default deny-all invalid profile allow-noflags; do
  echo
  echo "== container: $name"
  grep -o '"dev.youki.io_uring": "[^}]*}' $L/e2e/bundles/$name/config.json | sed 's/\\"/"/g' || echo "  (no policy)"
  $Y --root $STATE run --bundle $L/e2e/bundles/$name "c-$name" 2>&1 | grep -v "^\s*$" | sed 's/^/  /'
  $Y --root $STATE delete --force "c-$name" >/dev/null 2>&1
done
