#!/bin/bash
# A stock Ubuntu 26.04 cloud VM (own 7.0 kernel, systemd) inside WSL, to
# run youki in rootless mode with an io_uring policy.
set -e
D=~/iouring-lab/distro-vm
cd $D
BASE=https://cloud-images.ubuntu.com/resolute/current
IMG=resolute-server-cloudimg-amd64.img

if [ ! -f $IMG ]; then
  curl -sSfLO $BASE/$IMG
  curl -sSfL $BASE/SHA256SUMS -o SHA256SUMS
fi
grep " \*\?$IMG\$" SHA256SUMS | sed 's/ \*/  /' | sha256sum -c -

# Throwaway key for this VM only.
[ -f id_vm ] || ssh-keygen -q -t ed25519 -N '' -f id_vm -C iouring-lab-vm

cat > user-data <<EOF
#cloud-config
hostname: iouring-vm
users:
  - name: tester
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $(cat id_vm.pub)
package_update: true
packages: [uidmap, dbus-user-session, jq, busybox-static]
runcmd:
  - loginctl enable-linger tester
EOF
echo "instance-id: iouring-vm-1" > meta-data
cloud-localds seed.iso user-data meta-data

[ -f disk.qcow2 ] || { qemu-img create -q -f qcow2 -F qcow2 -b $IMG disk.qcow2 20G; }
echo "image and seed ready"
