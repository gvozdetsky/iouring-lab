#!/bin/bash
# Prepare bundles on the host, then run them with youki in a 7.2.9 guest.
bash ~/iouring-lab/e2e/prepare.sh || exit 1
bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/linux-7.2.9 /home/eugene/iouring-lab/e2e/guest.sh
