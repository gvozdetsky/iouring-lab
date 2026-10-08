# A restricted io_uring profile for containers: rationale

`default.json` is a candidate io_uring policy for container engines, in the
shape proposed for OCI `linux.ioUring`. It is built from two surveys done on
2026-10-08:
- which io_uring operations mainstream software uses (source survey of 15
  projects; see ../FINDINGS.md);
- where io_uring's security bugs have been (2020–2023 CVEs from NVD, kernel
  CNA CVEs 2024-02 to 2026-09, and the kCTF/kernelCTF exploit submissions).

## What it does

- **Allows 38 opcodes**: plain file I/O and metadata, polling, timeouts and
  cancel, and socket I/O. That covers every opcode used by io_uring paths that
  mainstream software enables by default.
- **Limits `IORING_OP_SOCKET`** to `AF_UNIX`, `AF_INET` and `AF_INET6`, matching
  the socket family allowlisting being added to seccomp profiles
  (moby/profiles#39). io_uring's socket opcode would otherwise bypass that.
- **Denies `IOSQE_BUFFER_SELECT` and `IOSQE_FIXED_FILE`** on every allowed
  operation. Provided buffers are the largest cluster of exploited io_uring
  bugs (Pwn2Own 2021, CVE-2021-41073, kernelCTF 0-days in 2025:
  CVE-2025-40364, CVE-2025-21836, CVE-2023-52926). The fixed file table
  (registered files, direct descriptors) is the second largest (CVE-2022-2602,
  CVE-2023-1872, CVE-2023-2236, CVE-2023-52656, all exploited).
- **Denies everything else**, including the opcodes with an exploitation or
  recent memory-safety history:

  | Opcode(s) | History |
  |---|---|
  | `MSG_RING` | exploited (CVE-2022-3910, ×4 kCTF), plus CVE-2023-2430 and CVE-2025-38453 |
  | `LINK_TIMEOUT` | exploited (CVE-2022-29582, CVE-2023-3389) |
  | `PROVIDE_BUFFERS`, `REMOVE_BUFFERS`, `READ_MULTISHOT` | the provided-buffer cluster above |
  | `URING_CMD`, `URING_CMD128` | a gateway into driver code: ublk, fuse, nvme, bsg; about 26 CVEs including consumers |
  | `SEND_ZC`, `SENDMSG_ZC`, `RECV_ZC` | memory-safety CVEs since 2025 |
  | `FUTEX_*`, `WAITID` | CVE-2025-39698, CVE-2025-40047 |
  | `READ_FIXED`, `WRITE_FIXED`, `READV_FIXED`, `WRITEV_FIXED` | depend on registered buffers (CVE-2023-2598 exploited, more in 2025–2026) |
  | `FIXED_FD_INSTALL`, `FILES_UPDATE`, `EPOLL_WAIT`, `TEE`, `MADVISE`, `OPENAT2`, `SETXATTR`, `FSETXATTR`, `NOP128` | used by none of the surveyed software |

## Compatibility

Works unchanged:
- every Node.js process (libuv's default `EPOLL_CTL` ring);
- PostgreSQL 18 `io_method=io_uring`;
- QEMU's default fd monitor and `aio=io_uring`;
- TigerBeetle;
- tokio's io_uring fs support;
- monoio;
- Seastar;
- RocksDB;
- MariaDB.

Breaks: these get `-EACCES` at run time, because the probe still reports the
operations as supported:
- **compio**, which uses buffer selection and zero-copy send; it is on by default;
- **Netty's io_uring transport**, which uses `LINK_TIMEOUT`, zero-copy and buffer selection; it is opt-in;
- **Envoy's experimental io_uring support**, which uses buffer selection;
- **glommio**, which is unmaintained and uses `LINK_TIMEOUT` and fixed buffers;
- **tokio-uring**, which is unmaintained;
- **Ceph BlueStore's opt-in io_uring backend**, which uses `FIXED_FILE`.

These need a wider, opt-in profile.

## What it does not cover (be explicit about this)

Opcode filtering can't reach everything. Of the 43 memory-safety CVEs the
kernel CNA published for io_uring from 2024-02 to 2026-09:

| Reachable through | Count | Share |
|---|---|---|
| Register opcodes | 15 | 35% |
| Setup flags | 5 | 12% |
| The core | 2 | 5% |
| Opcodes, provided buffers or zcrx (which this profile addresses) | 21 | 49% |

In the 23 kCTF/kernelCTF-exploited io_uring CVEs (mostly older kernels):

| Reachable through | Count |
|---|---|
| Core | 6 |
| Setup flags | 2 |
| Register opcodes | 5 |
| Both a register op and an opcode | 1 |
| Opcodes or provided buffers | 9 |

- **Register opcodes:** BPF filters can't see them. They can only be limited
  by the one-shot `IORING_REGISTER_RESTRICTIONS` allowlist. A runtime policy
  shouldn't use that allowlist, because it takes away the workload's ability
  to restrict itself further. Up to 7.3 the allowlist also doesn't hold:
  a ring created with `IORING_SETUP_R_DISABLED` accepts any register opcode
  until it is enabled (patch:
  https://lore.kernel.org/r/20261009-iouring-task-restrict-fix-v1-1-a49daf55a12c@gmail.com,
  see FINDINGS.md).
- **Setup flags** (`SQPOLL`, `IOPOLL`, `NO_MMAP`, `DEFER_TASKRUN`, and future
  ones) can't be filtered at all. seccomp can't read
  `struct io_uring_params`, and the task restrictions don't cover setup.
- **The core** (request lifecycle, io-wq, async poll) is reachable from any
  allowed opcode. That is about 1–2 memory-safety bugs a year on current
  kernels.

## Requirements

- **Kernel:** a kernel that keeps task restrictions across exec, CVE-2026-80713
  (bc0e8faf90e7). That means mainline 7.2+, 7.1.y with the backport, or a
  distribution kernel that carries it (Ubuntu 26.04: 7.0.0-39 or later).
  Plain 7.0 lets a workload drop the policy by using io_uring and then
  exec'ing.
- **seccomp:** the profile must allow `io_uring_setup`, `io_uring_enter` and
  `io_uring_register` for this profile to matter.

## Recommendation for engines

1. **Ship it as opt-in first, not as the default.** For example, a
   `--security-opt io_uring=restricted` switch that allows the three
   syscalls in seccomp and applies this profile. Keep blocking io_uring by
   default on any kernel without support, and the runtime must refuse,
   never ignore, a profile it can't enforce. That gives io_uring users a
   much better choice than `seccomp=unconfined`, without asking maintainers
   to accept the residual risk above for everyone.
2. **Consider making it the default only after these kernel gaps are closed:**
   - **Filtering of setup flags.** This is the largest unfilterable surface on
     modern kernels.
   - **BPF filtering of register opcodes,** so a runtime policy can restrict
     them without the one-shot allowlist.
   - **`IORING_REGISTER_PROBE` that reports denied opcodes as unsupported,** so
     tokio, compio, monoio, Netty and Seastar fall back instead of failing.
