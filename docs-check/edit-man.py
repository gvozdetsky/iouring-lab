#!/usr/bin/env python3
"""Apply the documentation update to man/io_uring_register_bpf_filter.3."""
import pathlib, sys

p = pathlib.Path.home() / "iouring-lab/liburing/man/io_uring_register_bpf_filter.3"
t = p.read_text()

def edit(old, new):
    global t
    if new in t:
        return
    if t.count(old) != 1:
        sys.exit(f"anchor found {t.count(old)} times: {old[:60]!r}")
    t = t.replace(old, new)

# 1. pdu_size of CONNECT in the description of pdu_size.
edit(""".BR IORING_OP_OPENAT " and " IORING_OP_OPENAT2
this would be 24 (three 8-byte members).
.PP
If the application's""",
""".BR IORING_OP_OPENAT " and " IORING_OP_OPENAT2
this would be 24 (three 8-byte members), and for
.B IORING_OP_CONNECT
also 24 (see below).
.PP
If the application's""")

# 2. The connect member in the context layout.
edit("""            __u64   resolve;   /* offset 32: resolve flags */
        } open;
    };""",
"""            __u64   resolve;   /* offset 32: resolve flags */
        } open;
        struct {
            __u32   family;    /* offset 16: address family */
            __be16  port;      /* offset 20: port, network order */
            __u8    pad[2];
            union {
                __be32  v4_addr;      /* offset 24: IPv4 address */
                __u8    v6_addr[16];  /* offset 24: IPv6 address */
            };
        } connect;
    };""")

# 3. CONNECT payload and how to load sub-word fields.
edit(""".I pdu_size
is set to 24 (three 8-byte members).
.SS Filter Stacking""",
""".I pdu_size
is set to 24 (three 8-byte members).
.PP
For
.B IORING_OP_CONNECT
operations (Linux 7.2 and later), the address family, port and address
are populated. The family is filled in only if the address length covers
it, and the port and address only if it covers a complete
.B struct sockaddr_in
or
.BR "struct sockaddr_in6" ;
otherwise they are zero. The port and the IPv4 address are in network
byte order.
.I pdu_size
is set to 24. On older kernels, filters for
.B IORING_OP_CONNECT
receive no payload and the kernel's
.I pdu_size
for it is 0.
.PP
A filter can only load 32-bit words
.RB ( "BPF_LD | BPF_W | BPF_ABS" )
at 4-byte aligned offsets within the context. To inspect a smaller field,
such as
.I sqe_flags
or the connect
.IR port ,
load the word that contains it and mask the result. Words are loaded in
host byte order, so on a little-endian machine
.I sqe_flags
is in bits 8 to 15 of the word at offset 8. See
.B Deny provided buffer selection
in EXAMPLES.
.SS Filter Stacking""")

# 4. Example: test an SQE flag.
edit(""".SS Discover kernel pdu_size for an opcode""",
""".SS Deny provided buffer selection
Load the word that holds
.I opcode
and
.IR sqe_flags ,
and deny the read if
.B IOSQE_BUFFER_SELECT
is set. Reads without it are allowed.
.PP
.in +4n
.EX
#include <endian.h>

#if __BYTE_ORDER == __LITTLE_ENDIAN
#define SQE_FLAGS_SHIFT  8
#else
#define SQE_FLAGS_SHIFT  16
#endif

struct sock_filter no_buffer_select[] = {
    /* Load the word holding opcode, sqe_flags and pdu_size */
    BPF_STMT(BPF_LD | BPF_W | BPF_ABS, 8),
    /* If IOSQE_BUFFER_SELECT is set, deny */
    BPF_JUMP(BPF_JMP | BPF_JSET | BPF_K,
             IOSQE_BUFFER_SELECT << SQE_FLAGS_SHIFT, 0, 1),
    BPF_STMT(BPF_RET | BPF_K, 0),
    BPF_STMT(BPF_RET | BPF_K, 1),
};

struct io_uring_bpf bpf = {
    .cmd_type = IO_URING_BPF_CMD_FILTER,
    .filter = {
        .opcode = IORING_OP_READ,
        .filter_len = 4,
        .filter_ptr = (unsigned long) no_buffer_select,
    },
};

io_uring_register_bpf_filter(&ring, &bpf);
.EE
.in
.SS Discover kernel pdu_size for an opcode""")

# 5. exec and the interaction with task opcode restrictions.
edit("""Children can add additional restrictions but cannot remove or
weaken filters set by their ancestors.
""",
"""Children can add additional restrictions but cannot remove or
weaken filters set by their ancestors.
.PP
Task-level filters are also kept across
.BR execve (2).
Kernels before Linux 7.2 dropped them on
.BR execve (2)
if the task had already used io_uring, unless they carry commit
bc0e8faf90e7 ("io_uring: preserve task restrictions across exec").
.PP
A task-level filter counts as task restrictions: once one is
registered, registering a task-level opcode allowlist with
.B IORING_REGISTER_RESTRICTIONS
on file descriptor \\-1 fails with
.BR \\-EPERM .
If both are used, register the opcode allowlist first.
""")

p.write_text(t)
print("man page updated")
