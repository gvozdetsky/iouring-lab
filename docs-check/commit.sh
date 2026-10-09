#!/bin/bash
cd ~/iouring-lab/liburing || exit 1
G="-c user.name=Eugene_Gvozdetsky -c user.email=gvozdet@gmail.com"
git add src/include/liburing/io_uring/bpf_filter.h
git -c user.name="Eugene Gvozdetsky" -c user.email="gvozdet@gmail.com" commit -q -F - <<'EOF'
io_uring/bpf_filter.h: update for IORING_OP_CONNECT

Sync with the kernel uapi header. Since 899bea8248ce ("io_uring/net:
allow filtering on IORING_OP_CONNECT"), Linux 7.2 passes the address
family, port and address of IORING_OP_CONNECT to BPF filters. The new
union member doesn't change the size of struct io_uring_bpf_ctx.

Assisted-by: Claude:claude-opus-5-5
EOF
git add man/io_uring_register_bpf_filter.3
git -c user.name="Eugene Gvozdetsky" -c user.email="gvozdet@gmail.com" commit -q -F - <<'EOF'
man/io_uring_register_bpf_filter.3: document CONNECT, word loads and exec

- IORING_OP_CONNECT filtering (Linux 7.2): the context layout, when the
  fields are populated, and its pdu_size.
- Filters can only load aligned 32-bit words. Explain how to test
  sqe_flags, with an example that denies provided-buffer selection.
- Task filters are kept across exec; older kernels dropped them once the
  task had used io_uring (bc0e8faf90e7).
- A task filter makes a later task IORING_REGISTER_RESTRICTIONS fail
  with -EPERM, so register the opcode allowlist first.

Checked on 7.0 and 7.2.9: the CONNECT pdu_size write-back (0 on 7.0,
24 on 7.2.9), the example (reads allowed, reads with buffer selection
get -EACCES), and the -EPERM ordering.

Assisted-by: Claude:claude-opus-5-5
EOF
git log --oneline -3
git show --stat --format='%h %s' HEAD~1 HEAD | grep -v '^$'
