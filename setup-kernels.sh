#!/bin/bash
# Fetch, configure and build the lab kernels from scratch on a new machine:
# the virtme-ng minimal config, plus io_uring BPF filters and what youki
# containers and liburing's tests need.
# usage: setup-kernels.sh [version...]   (default: 7.2.9 7.0)
set -e
cd ~/iouring-lab
vs=("$@"); [ $# -gt 0 ] || vs=(7.2.9 7.0)
for v in "${vs[@]}"; do
  if [ ! -d linux-$v ]; then
    curl -sSfLO https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$v.tar.xz
    curl -sSfL https://cdn.kernel.org/pub/linux/kernel/v7.x/sha256sums.asc |
      grep " linux-$v.tar.xz\$" | sha256sum -c -
    tar xJf linux-$v.tar.xz && rm linux-$v.tar.xz
  fi
  cd linux-$v
  [ -f .config ] || vng --kconfig
  opts="IO_URING BPF BPF_SYSCALL IO_URING_BPF SECCOMP SECCOMP_FILTER
    NAMESPACES USER_NS PID_NS NET_NS IPC_NS UTS_NS TIME_NS
    CGROUPS CGROUP_PIDS MEMCG CGROUP_SCHED CGROUP_FREEZER CGROUP_DEVICE
    CGROUP_BPF CPUSETS BLK_CGROUP POSIX_MQUEUE OVERLAY_FS VETH IPV6 KEYS"
  ./scripts/config $(printf -- '--enable %s ' $opts)
  make olddefconfig >/dev/null
  for o in $opts; do
    grep -q "^CONFIG_$o=y" .config || echo "linux-$v: CONFIG_$o not set"
  done
  start=$(date +%s)
  make -j"$(nproc)" bzImage 2>&1 | grep -E " error |Kernel: arch" | tail -5
  echo "linux-$v: build seconds: $(( $(date +%s) - start ))"
  cd ..
done
