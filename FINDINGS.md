# io_uring restrictions for containers — lab findings

Evidence for an OCI runtime-spec proposal and a default container profile.
Everything below was run, not just read; scripts are in this repo.

## Kernel API (verified on 7.2.9 in virtme-ng; probe/vm-tests.sh)

| # | Claim | Result |
|---|---|---|
| 1 | Task-level registration uses `io_uring_register(-1, …)` | works |
| 2 | Needs `no_new_privs` or `CAP_SYS_ADMIN` in the caller's user namespace | non-root without NNP: `EACCES`; root: ok; uid 1000 inside `unshare --user`: ok (e2e/guest-rootless.sh) |
| 3 | `IORING_REGISTER_RESTRICTIONS` (task) restricts opcodes | works, **and** denies every SQE flag not explicitly allowed (`IO_LINK` denied until allowed) |
| 4 | It can be registered once per task | nested registration: `EPERM` |
| 5 | cBPF filter on `IORING_OP_SOCKET` by family | netlink denied, inet/unix allowed |
| 6 | BPF-only allowlist (allow-all filter per op + `DENY_REST`) | works; SQE flags unaffected |
| 7 | Restrictions are inherited across fork and exec | yes |
| 8 | BPF filters stack and only tighten | nested narrowing works, on top of BPF and on top of an opcode allowlist |
| 9 | Feature probe: `io_uring_register(-1, BPF_FILTER, NULL, 1)` | 7.x: `EFAULT`; 6.18: `EINVAL` (older kernels: `EBADF`) |

### Linux 7.0 (Ubuntu 26.04 LTS base): restrictions lost on exec

Same scenarios on mainline 7.0: claims 1–9 hold, but scenario 11 fails.
A restricted task that has used io_uring (created a ring) and then execs runs
the new image **without restrictions**: `__io_uring_free()` on the exec path
freed the task restriction together with the task context. Inside a container
that is a bypass: open a ring, exec anything.

- Fixed upstream in bc0e8faf90e7 "io_uring: preserve task restrictions across
  exec" (7.2, 2026-07-30), tagged `Cc: stable # 7.1+`, so not for 7.0.y.
- Ubuntu: absent from 7.0.0-38 (current 26.04 kernel); backported in
  7.0.0-39.39 (in -proposed, uploaded 2026-09-24).
- The youki e2e containers pass on 7.0 because `iou-check` itself doesn't exec
  after using a ring; the kernel bug is still reachable by a workload.
- Consequence: a version check can't tell a fixed 7.0/7.1 distro kernel from
  an unfixed one. Options for runtimes: a one-off self-test (fork, restrict,
  use a ring, exec a checker, verify the restriction survived) or a documented
  minimum (mainline 7.2, Ubuntu 7.0.0-39). To raise in the proposal.

## Design consequences

- A runtime policy should be built from **BPF filters only**: it leaves SQE flags
  alone and lets the workload add its own, tighter filters (claims 3, 4, 8).
- Apply it in the container init **before seccomp** (seccomp may deny
  `io_uring_register`) and **before capabilities are dropped** (claim 2), the
  same place and rules as seccomp. This also covers rootless runtimes.
- Fail closed: a container with a policy must not start on a kernel that can't
  enforce it (claim 9).
- Only `SOCKET`, `OPENAT`/`OPENAT2` and (7.2+) `CONNECT` expose arguments to
  filters; everything else is allow/deny per opcode.

## youki prototype (branch `io-uring-restrictions` in ~/iouring-lab/youki)

Policy in the `dev.youki.io_uring` annotation:
`{"defaultAction": "deny"|"allow", "ops": ["IORING_OP_…"], "socketFamilies": ["AF_…"]}`

- `crates/libcontainer/src/io_uring.rs`: parse, compile to cBPF, register, feature probe; 8 unit tests.
- `process/init/process.rs`: applied before the first seccomp block.
- `validator.rs`: rejects a policy on a kernel without support, before anything is created.

End-to-end (e2e/guest.sh, real youki containers on 7.2.9):

| Container | Result |
|---|---|
| no policy | everything allowed |
| deny + {NOP, SOCKET, OPENAT}, families {UNIX, INET, INET6} | netlink denied, rest allowed |
| allow, deny OPENAT, families {INET} | openat, unix and netlink sockets denied |
| deny, no ops | everything denied |
| invalid opcode name | refused: `unknown io_uring opcode read` |
| policy on WSL 6.18 (rootless, e2e/old-kernel.sh) | refused: `io_uring restrictions are not supported by this kernel` |

All inherited by processes forked inside the container.

## What mainstream software needs (input for a default profile)

Source survey (2026-10-08) of PostgreSQL 18, libuv/Node.js, tokio, tokio-uring,
monoio, compio, Netty 4.2, RocksDB, TigerBeetle, QEMU, Seastar/ScyllaDB,
glommio, MariaDB, Ceph BlueStore and Envoy.

- Opcodes used by io_uring paths that are **on by default**: READ, READV,
  WRITE, WRITEV, FSYNC, EPOLL_CTL, POLL_ADD, POLL_REMOVE, TIMEOUT, NOP, ACCEPT,
  CONNECT, SEND, RECV, SENDMSG, RECVMSG, CLOSE, OPENAT, STATX, ASYNC_CANCEL.
- All opcodes used by any of them (43): the above plus READ/WRITE_FIXED,
  TIMEOUT_REMOVE, LINK_TIMEOUT, FALLOCATE, SPLICE, PROVIDE_BUFFERS, SHUTDOWN,
  RENAMEAT, UNLINKAT, MKDIRAT, SYMLINKAT, LINKAT, FTRUNCATE, SEND_ZC,
  SENDMSG_ZC, SOCKET, BIND, LISTEN, PIPE, GETXATTR, FGETXATTR, READ_MULTISHOT.
- Used by none: SYNC_FILE_RANGE, FILES_UPDATE, FADVISE, MADVISE, OPENAT2,
  REMOVE_BUFFERS, TEE, MSG_RING, SETXATTR, FSETXATTR, URING_CMD(128), WAITID,
  FUTEX_*, FIXED_FD_INSTALL, RECV_ZC, EPOLL_WAIT, READV/WRITEV_FIXED, NOP128.

Traps:

1. `IORING_REGISTER_PROBE` reports every opcode the kernel supports, ignoring
   restrictions. tokio, compio, monoio, Seastar, Netty and glommio choose
   their fallbacks by probing, so a denied op never triggers a fallback: it
   fails with -EACCES at run time. **Kernel improvement to propose:** mask
   denied opcodes in the probe result.
2. libuv (every Node.js process) uses an EPOLL_CTL ring by default and
   `abort()`s on an unexpected CQE error: a default profile must allow
   EPOLL_CTL (or fail `io_uring_setup` instead).
3. Many users set SQE flags (ASYNC, IO_LINK, HARDLINK, DRAIN, BUFFER_SELECT,
   FIXED_FILE): the BPF-only policy leaves them alone; the opcode allowlist
   would break them.
4. Setup flags are not filtered by these mechanisms; liburing retries ring
   setup only on -EINVAL.
5. Some users have no fallback (TigerBeetle, glommio, tokio-uring, monoio's
   IoUringDriver, PostgreSQL with io_method=io_uring): a denied op mid-run is
   an I/O error to them.

## Open points

- youki rootless mode needs systemd for cgroups, so the full rootless
  container run needs a host with systemd and a 7.x kernel.
- Restrictions persist across exec only since 7.2 (bc0e8faf) for tasks that
  already used io_uring; check 7.0 (Ubuntu 26.04 LTS).
- Only rings created after registration are restricted: a ring fd passed in
  from outside the container is not. Document in the proposal.
