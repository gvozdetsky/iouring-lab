#!/bin/bash
# Copy binaries into the VM and run in-vm.sh there as "tester".
D=~/iouring-lab/distro-vm
L=~/iouring-lab
SCP="scp -q -P 2222 -i $D/id_vm -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH="ssh -q -p 2222 -i $D/id_vm -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null tester@127.0.0.1"
$SCP $L/youki/target/release/youki $L/probe/target/x86_64-unknown-linux-gnu/release/iou-check \
     $L/profile/default.json $D/in-vm.sh $D/apparmor.sh tester@127.0.0.1:
$SSH 'bash ~/apparmor.sh'
# A login shell gives the session D-Bus and XDG_RUNTIME_DIR youki needs.
$SSH 'bash -lc "bash ~/in-vm.sh"'
