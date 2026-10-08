#!/bin/bash
cd ~/iouring-lab/liburing || exit 1
git log --format='%s' -20 | grep -i '^test' | head -5
git checkout -q -B task-restrict-exec
git add test/task-restrict-exec.c test/Makefile
git -c user.name="Eugene Gvozdetsky" -c user.email="gvozdet@gmail.com" commit -q -F - <<'EOF'
test: check that per-task restrictions survive exec

Per-task io_uring restrictions must keep applying to rings created after
exec, also when the task used io_uring before exec. Kernels without
commit bc0e8faf90e7 ("io_uring: preserve task restrictions across exec")
free the restrictions with the task context on exec in that case, so the
new image can create unrestricted rings. task-restrict.t doesn't cover
exec, so it passes on those kernels.

Restrict a child to NOP, optionally use a ring, re-exec the test and
check that a fresh ring still denies a read. Cover both the opcode
allowlist and a BPF filter.

Skips on 6.18, fails on 7.0, passes on 7.2.9.

Assisted-by: Claude:claude-opus-5-5
EOF
git log --oneline -1; git show --stat --format= HEAD
