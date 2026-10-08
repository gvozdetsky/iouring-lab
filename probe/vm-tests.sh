#!/bin/bash
# Runs inside the virtme-ng guest. Each scenario checks one claim about the
# Linux 7.x task-level io_uring restriction API that the runtime design relies on.
U="setpriv --reuid=1000 --regid=1000 --clear-groups"
R="$U /home/eugene/iouring-lab/probe/target/release/iou-restrict"
C=/home/eugene/iouring-lab/probe/target/release/iou-check
R0=/home/eugene/iouring-lab/probe/target/release/iou-restrict  # inner level, already unprivileged
# opcodes: 0 NOP, 18 OPENAT, 45 SOCKET; IOSQE_IO_LINK = 4; AF_UNIX 1, AF_INET 2, AF_INET6 10
echo "== guest kernel $(uname -r), uid $(id -u), io_uring_disabled=$(cat /proc/sys/kernel/io_uring_disabled)"

echo; echo "== 1. no restrictions (baseline)"
$U $C

echo; echo "== 2. without NO_NEW_PRIVS: non-root must get EACCES, root (CAP_SYS_ADMIN) may register"
$R --ops 0 -- $C | head -3
echo "  -- as root:"; /home/eugene/iouring-lab/probe/target/release/iou-restrict --ops 0 -- $C | head -3

echo; echo "== 3. ops allowlist {NOP, SOCKET}, no SQE flags: openat and IO_LINK denied"
$R --nnp --ops 0,45 -- $C

echo; echo "== 4. same + IO_LINK allowed: linked NOPs pass"
$R --nnp --ops 0,45 --sqe-flags 4 -- $C

echo; echo "== 5. socket families {UNIX, INET, INET6}: netlink denied, rest allowed"
$R --nnp --socket-families 1,2,10 -- $C

echo; echo "== 6. BPF-only allowlist {NOP, SOCKET} + DENY_REST: openat denied, SQE flags unrestricted"
$R --nnp --bpf-allow 0,45 -- $C

echo; echo "== 7. inheritance across fork (and exec, which iou-restrict already did)"
$R --nnp --socket-families 2 -- $C --fork

echo; echo "== 8. ops allowlist is one-shot: a nested allowlist must fail with EPERM"
$R --nnp --ops 0,18,45 -- $R0 --ops 0 -- $C

echo; echo "== 9. BPF stacks: outer allows {NOP, OPENAT, SOCKET}, inner narrows sockets to INET"
$R --nnp --bpf-allow 0,18,45 -- $R0 --socket-families 2 -- $C

echo; echo "== 10. ops allowlist then BPF on top (runtime policy + app self-restriction)"
$R --nnp --ops 0,18,45 --sqe-flags 4 -- $R0 --socket-families 2 -- $C
