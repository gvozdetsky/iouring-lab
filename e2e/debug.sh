#!/bin/bash
for f in /etc/os-release /usr/lib/os-release /proc/meminfo /proc/self/mountinfo /proc/self/exe /proc/cpuinfo /sys/fs/cgroup/cgroup.controllers /sys/fs/cgroup/cgroup.subtree_control /proc/sys/kernel/osrelease /dev/null /dev/stderr /proc/self/fd/2; do
  if [ -e "$f" ]; then echo "ok      $f"; else echo "MISSING $f"; fi
done
ls -la /dev/stderr /proc/self/fd/ 2>&1 | head
cat /proc/self/mountinfo | awk '{print $5, $9}' | head -30
