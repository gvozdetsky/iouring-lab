#!/bin/bash
# Prepare an OCI bundle per scenario: busybox rootfs + a static iou-check.
set -e
L=~/iouring-lab
. ~/.cargo/env 2>/dev/null
cd $L/probe
RUSTFLAGS="-C target-feature=+crt-static" cargo build --release --target x86_64-unknown-linux-gnu --bin iou-check 2>&1 | grep -E "^(warning|error)|Finished"
CHECK=$L/probe/target/x86_64-unknown-linux-gnu/release/iou-check
file $CHECK | grep -qE "statically linked|static-pie linked" || { echo "iou-check is not static"; exit 1; }

ROOTFS=$L/e2e/rootfs
rm -rf $ROOTFS && mkdir -p $ROOTFS/{bin,etc,proc,sys,dev,tmp}
cp /bin/busybox $ROOTFS/bin/busybox
for t in sh ls cat echo; do ln -sf busybox $ROOTFS/bin/$t; done
cp $CHECK $ROOTFS/bin/iou-check
echo ruxen-lab > $ROOTFS/etc/hostname

# One bundle per scenario; config.json from `youki spec`, edited with jq-less python.
mk() {
  local name=$1 annotation=$2
  local b=$L/e2e/bundles/$name
  rm -rf $b && mkdir -p $b
  ln -s $ROOTFS $b/rootfs
  (cd $b && $L/youki/target/release/youki spec >/dev/null)
  python3 - "$b/config.json" "$annotation" <<'EOF'
import json, sys
path, annotation = sys.argv[1], sys.argv[2]
c = json.load(open(path))
c["process"]["terminal"] = False
c["process"]["args"] = ["/bin/iou-check", "--fork"]
c["root"]["readonly"] = True
if annotation:
    c.setdefault("annotations", {})["dev.youki.io_uring"] = annotation
json.dump(c, open(path, "w"), indent=2)
EOF
  echo "bundle $name ready"
}

mk none ""
mk deny-default '{"defaultAction":"deny","ops":["IORING_OP_NOP","IORING_OP_SOCKET","IORING_OP_OPENAT"],"socketFamilies":["AF_UNIX","AF_INET","AF_INET6"]}'
mk allow-default '{"defaultAction":"allow","ops":["IORING_OP_OPENAT"],"socketFamilies":["AF_INET"]}'
mk deny-all '{"defaultAction":"deny"}'
mk invalid '{"defaultAction":"deny","ops":["read"]}'
mk profile "$(python3 -c 'import json; print(json.dumps(json.load(open("'$L'/profile/default.json")), separators=(",",":")))')"
mk allow-noflags '{"defaultAction":"allow","ops":["IORING_OP_MSG_RING"],"deniedSqeFlags":["IOSQE_BUFFER_SELECT"]}'
