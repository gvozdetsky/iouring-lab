#!/bin/bash
cd ~/iouring-lab/linux-7.2.9 || exit 1
echo "compilers running: $(pgrep -c cc1)"
ls -la arch/x86/boot/bzImage 2>/dev/null || echo "bzImage not yet"
grep -E '^CONFIG_(IO_URING|IO_URING_BPF|BPF|NET|SECCOMP)=' .config
