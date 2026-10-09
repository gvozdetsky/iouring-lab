#!/bin/bash
# Enable what container runtimes and liburing's tests need on top of the
# virtme-ng minimal config.
cd ~/iouring-lab/linux-7.2.9 || exit 1
start=$(date +%s)
./scripts/config --enable USER_NS --enable MEMCG --enable VETH --enable IPV6
make olddefconfig >/dev/null
grep -E '^CONFIG_(USER_NS|MEMCG|VETH|IPV6|IO_URING_BPF)=' .config
make -j"$(nproc)" bzImage 2>&1 | grep -E " error |Kernel: arch" | tail -5
echo "rebuild seconds: $(( $(date +%s) - start ))"
