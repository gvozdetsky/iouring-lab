#!/bin/bash
# Shut the VM down cleanly (start.sh boots it again; the disk is kept).
D=~/iouring-lab/distro-vm
ssh -q -p 2222 -i $D/id_vm -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null tester@127.0.0.1 'sudo systemctl poweroff' 2>/dev/null
for i in $(seq 1 30); do kill -0 "$(cat $D/vm.pid 2>/dev/null)" 2>/dev/null || { echo "VM stopped"; exit 0; }; sleep 1; done
echo "VM still running"
