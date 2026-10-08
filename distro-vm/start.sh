#!/bin/bash
# Start the VM in the background (ssh on localhost:2222) and wait for it.
D=~/iouring-lab/distro-vm
cd $D
if ! [ -f vm.pid ] || ! kill -0 "$(cat vm.pid)" 2>/dev/null; then
  qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 3G \
    -drive file=disk.qcow2,if=virtio -drive file=seed.iso,if=virtio,format=raw \
    -nic user,model=virtio,hostfwd=tcp:127.0.0.1:2222-:22 \
    -display none -serial file:console.log -daemonize -pidfile vm.pid
fi
SSH="ssh -q -p 2222 -i $D/id_vm -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 tester@127.0.0.1"
for i in $(seq 1 60); do
  if $SSH 'cloud-init status --wait >/dev/null 2>&1; true' 2>/dev/null; then
    $SSH 'echo "vm up: $(uname -r), $(systemctl --user is-system-running 2>/dev/null || echo user-systemd?)"; cloud-init status'
    exit 0
  fi
  sleep 5
done
echo "VM did not come up; tail of console:"; tail -20 console.log; exit 1
