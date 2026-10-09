#!/bin/bash
cd ~/iouring-lab/liburing || exit 1
python3 ~/iouring-lab/docs-check/edit-man.py || exit 1
M=man/io_uring_register_bpf_filter.3
echo "--- groff warnings (none expected)"
groff -man -ww -z -Tutf8 $M 2>&1 | head
echo "--- rendered new parts"
MANWIDTH=80 man -l $M 2>/dev/null | col -b | awk '/also 24|For IORING_OP_CONNECT operations|A filter can only load|Deny provided buffer selection|kept across|counts as task restrictions/{p=12} p-- > 0'
git diff --stat
