#!/bin/bash
# Run the API scenarios and the youki e2e containers on Linux 7.0.
tail -2 /dev/null
ls -la ~/iouring-lab/linux-7.0/arch/x86/boot/bzImage || exit 1
echo "######## API scenarios on 7.0"
bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/linux-7.0
echo "######## youki containers on 7.0"
bash ~/iouring-lab/probe/run-vm.sh ~/iouring-lab/linux-7.0 /home/eugene/iouring-lab/e2e/guest.sh
