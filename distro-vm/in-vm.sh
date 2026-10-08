#!/bin/bash
# Runs inside the Ubuntu 26.04 VM as the unprivileged user "tester":
# rootless youki containers with and without an io_uring policy.
cd ~ || exit 1
echo "== $(lsb_release -ds), kernel $(uname -r), uid $(id -u)"
echo "   CONFIG_IO_URING_BPF: $(grep -h '^CONFIG_IO_URING_BPF=' /boot/config-$(uname -r) || echo unset)"
echo "   kernel.io_uring_disabled: $(cat /proc/sys/kernel/io_uring_disabled)"
echo "   user cgroup controllers: $(cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers 2>/dev/null)"
echo "   XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unset}"

Y=~/youki
rm -rf rootfs bundles && mkdir -p rootfs/{bin,etc,proc,sys,dev,tmp} bundles
cp /bin/busybox rootfs/bin/ && ln -sf busybox rootfs/bin/sh
cp ~/iou-check rootfs/bin/iou-check
echo iouring-vm > rootfs/etc/hostname
PROFILE=$(jq -c . ~/default.json)

mk() {
  local name=$1 policy=$2 b=~/bundles/$1
  mkdir -p $b && ln -s ~/rootfs $b/rootfs
  (cd $b && $Y spec --rootless >/dev/null)
  jq --arg p "$policy" '.process.terminal=false | .process.args=["/bin/iou-check","--fork"] | .root.readonly=true
      | if $p == "" then . else .annotations["dev.youki.io_uring"]=$p end' $b/config.json > $b/c && mv $b/c $b/config.json
}
mk none ""
mk profile "$PROFILE"
mk invalid '{"defaultAction":"deny","ops":["read"]}'

for name in none profile invalid; do
  echo; echo "== rootless container: $name"
  $Y run --bundle ~/bundles/$name rl-$name 2>&1 | sed 's/^/  /'
  echo "  exit=$?"
  $Y delete --force rl-$name >/dev/null 2>&1
done
