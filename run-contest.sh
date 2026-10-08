#!/bin/bash
cd ~/iouring-lab/youki && [ -f bundle.tar.gz ] || cp tests/contest/contest/bundle.tar.gz bundle.tar.gz
ls -la ~/iouring-lab/youki/bundle.tar.gz || exit 1
for k in linux-7.2.9 linux-7.0; do
  echo "################ $k"
  bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/$k /home/eugene/iouring-lab/e2e/guest-contest.sh | grep -v -e modules.order -e '^$'
done
