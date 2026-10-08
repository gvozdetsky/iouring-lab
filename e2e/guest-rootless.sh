#!/bin/bash
# Inside the guest: the rootless path. An unprivileged user (uid 1000) gets
# CAP_SYS_ADMIN only inside a new user namespace, which is what lets a
# rootless runtime's init register filters without no_new_privs.
# (youki's own rootless mode needs systemd for cgroups, absent in the guest.)
P=/home/eugene/iouring-lab/probe/target/release
U="setpriv --reuid=1000 --regid=1000 --clear-groups"
echo "-- uid 1000, no user namespace, no NNP (must be EACCES):"
$U $P/iou-restrict --socket-families 2 -- $P/iou-check 2>&1 | head -2 | sed 's/^/  /'
echo "-- uid 1000 in a new user namespace, no NNP (must succeed and apply):"
$U unshare --user --map-root-user $P/iou-restrict --socket-families 2 -- $P/iou-check 2>&1 | sed 's/^/  /'
