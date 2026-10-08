#!/bin/bash
# Boot a kernel tree in virtme-ng and run vm-tests.sh inside it.
# usage: run-vm.sh [kernel-tree] [guest-script]
#   kernel-tree default: ~/iouring-lab/linux-7.2.9
#   guest-script default: ~/iouring-lab/probe/vm-tests.sh
# vng needs a pty; `script` provides one when we're driven non-interactively.
K=${1:-$HOME/iouring-lab/linux-7.2.9}
S=${2:-$HOME/iouring-lab/probe/vm-tests.sh}
cd ~/iouring-lab/probe || exit 1
script -qec "vng --run '$K' --memory 1G --exec 'bash $S'" /dev/null | tr -d '\r'
