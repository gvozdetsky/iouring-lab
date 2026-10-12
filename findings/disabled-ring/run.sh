#!/bin/bash
# Build the disabled-ring reproducer and run it as an unprivileged user in
# the 7.0 and 7.2.9 VMs. Paths resolve from the repo, not a fixed home.
# Generated artifacts (the binary and guest.sh) land in build/ and stay out
# of git.
set -e
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
build="$here/build"
mkdir -p "$build"

cc -Wall -O2 -o "$build/repro" "$here/repro.c" -I "$repo/linux-7.2.9/usr/include" 2>&1
[ -d "$repo/linux-7.2.9/usr/include/linux" ] || echo "(using system headers)"

# $build expands here (host) to an absolute path the VM also sees; the
# runtime bits ($(uname -r), $?) are escaped so they run in the guest.
cat > "$build/guest.sh" <<EOF
echo "kernel \$(uname -r)"
setpriv --reuid=1000 --regid=1000 --clear-groups "$build/repro"; echo "exit=\$?"
EOF

for k in linux-7.0 linux-7.2.9; do
  bash "$repo/probe/run-vm.sh" "$repo/$k" "$build/guest.sh" | grep -v modules.order | grep -v '^$'
done
