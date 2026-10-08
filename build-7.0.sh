#!/bin/bash
# Build mainline 7.0 (what Ubuntu 26.04 LTS ships) with the same config.
set -e
cd ~/iouring-lab
[ -d linux-7.0 ] || curl -sSL https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.0.tar.xz | tar xJ
cd linux-7.0
cp ../linux-7.2.9/.config .config
make olddefconfig >/dev/null
grep -E '^CONFIG_(USER_NS|MEMCG|IO_URING_BPF)=' .config
start=$(date +%s)
make -j"$(nproc)" bzImage 2>&1 | grep -E " error |Kernel: arch" | tail -5
echo "build seconds: $(( $(date +%s) - start ))"
