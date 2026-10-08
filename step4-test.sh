#!/bin/bash
# Rebuild youki and the probe, then run the e2e containers on 7.2.9 and 7.0.
bash ~/iouring-lab/build-youki.sh 2>&1 | grep -v "^Warning: can't set"
cd ~/iouring-lab/probe && . ~/.cargo/env && cargo build --release 2>&1 | grep -E '^(warning|error)|Finished'
bash ~/iouring-lab/e2e/prepare.sh || exit 1
for k in linux-7.2.9 linux-7.0; do
  echo "################ $k"
  bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/$k /home/eugene/iouring-lab/e2e/guest.sh | grep -v modules.order | \
    awk '/== container: (profile|allow-noflags|deny-default)/{p=1} /== container: (none|allow-default|deny-all|invalid)/{p=0} p'
done
