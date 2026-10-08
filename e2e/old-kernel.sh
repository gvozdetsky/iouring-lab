#!/bin/bash
# On a kernel without task-level io_uring restrictions (WSL 6.18), a container
# with a policy must be refused before anything is created; without a policy
# it must still run. Rootless, so no root is needed on the host.
L=~/iouring-lab
Y=$L/youki/target/release/youki
B=$L/e2e/bundles-rootless
rm -rf $B && mkdir -p $B/plain $B/policy
for b in plain policy; do
  ln -s $L/e2e/rootfs $B/$b/rootfs
  (cd $B/$b && $Y spec --rootless >/dev/null)
done
python3 - $B/plain/config.json $B/policy/config.json <<'EOF'
import json, sys
for i, path in enumerate(sys.argv[1:]):
    c = json.load(open(path))
    c["process"]["terminal"] = False
    c["process"]["args"] = ["/bin/iou-check"]
    c["root"]["readonly"] = True
    if i == 1:
        c.setdefault("annotations", {})["dev.youki.io_uring"] = '{"defaultAction":"deny","ops":["IORING_OP_NOP"]}'
    json.dump(c, open(path, "w"), indent=2)
EOF
echo "== host kernel $(uname -r), uid $(id -u)"
echo "-- rootless container without a policy:"
$Y run --bundle $B/plain old-plain 2>&1 | head -4 | sed 's/^/  /'
$Y delete --force old-plain >/dev/null 2>&1
echo "-- rootless container with a policy (must be refused):"
$Y run --bundle $B/policy old-policy 2>&1 | head -4 | sed 's/^/  /'
$Y delete --force old-policy >/dev/null 2>&1
