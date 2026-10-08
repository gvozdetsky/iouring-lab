Title: Proposal: `linux.ioUring` to restrict io_uring operations (Linux 7.0+)

### Problem

io_uring operations are submitted through a ring in shared memory, not as
syscalls, so seccomp can't filter them. That is why the default profiles of
Docker and containerd (moby/moby#46762, containerd/containerd#9320) and
Podman block `io_uring_setup`, `io_uring_enter` and `io_uring_register`
entirely. Users must choose between no io_uring at all and an unconfined
container.

Linux 7.0 added task-level io_uring restrictions with classic BPF filters per
opcode ([pull request](https://lkml.iu.edu/hypermail/linux/kernel/2602.0/09693.html),
[LWN](https://lwn.net/Articles/1054225/)). They are designed for exactly this
case:

- registered with `io_uring_register(-1, …)`;
- inherited across fork and exec;
- can only be tightened;
- need `no_new_privs` or `CAP_SYS_ADMIN` in the user namespace, as seccomp does.

The kernel pull request names containers and systemd as the consumers. As far
as I can tell, no runtime and no spec uses them yet.

### Proposal

A new optional `linux.ioUring` object:

```json
"ioUring": {
    "defaultAction": "deny",
    "ops": ["IORING_OP_READ", "IORING_OP_WRITE", "IORING_OP_SEND",
            "IORING_OP_RECV", "IORING_OP_ACCEPT", "IORING_OP_SOCKET"],
    "socketFamilies": ["AF_UNIX", "AF_INET", "AF_INET6"]
}
```

- **`defaultAction`** *(string, REQUIRED)*: `deny` or `allow`. It applies to
  opcodes not listed in `ops`.
- **`ops`** *(array of strings, OPTIONAL)*: opcode names from `enum io_uring_op`
  in `<linux/io_uring.h>`. With `deny`, these are the only opcodes allowed.
  With `allow`, these are the opcodes denied. The runtime MUST generate an
  error for a name it doesn't know.
- **`socketFamilies`** *(array of strings, OPTIONAL)*: while
  `IORING_OP_SOCKET` is allowed, only these address families may be created.
  Names are as in `<sys/socket.h>`.
- **`deniedSqeFlags`** *(array of strings, OPTIONAL)*: `IOSQE_*` flag names.
  Any otherwise allowed operation submitted with one of these flags is denied.
  This is mainly for `IOSQE_BUFFER_SELECT` (provided buffers, the largest
  cluster of exploited io_uring bugs) and `IOSQE_FIXED_FILE`.

Semantics:

- The runtime MUST apply the restrictions before the container process
  executes, so the process and all its descendants are restricted. A denied
  operation completes with `-EACCES`.
- If the kernel can't enforce the restrictions, the runtime MUST generate an
  error. It MUST NOT ignore them.
- `features.json`: `linux.ioUring` with `enabled`, plus the known `ops` and
  `socketFamilies` names, as for seccomp.

Implementation notes, from the prototype:

- Apply the restrictions **before seccomp**, because a profile may deny
  `io_uring_register`.
- Apply them **before capabilities are dropped**. Registration needs
  `CAP_SYS_ADMIN` in the user namespace or `no_new_privs`, the same as
  seccomp. That also works for rootless runtimes.
- Build the policy only from BPF filters: an allow filter per listed opcode,
  then `IO_URING_BPF_FILTER_DENY_REST`. Don't use the task opcode allowlist
  (`IORING_REGISTER_RESTRICTIONS`). That allowlist also denies every SQE flag
  not explicitly allowed, and a task can register it only once, so the
  workload could no longer add its own tighter restrictions. BPF filters
  stack.

This complements seccomp; it doesn't replace it. On kernels that support
`ioUring`, an engine could change its default from "block io_uring in
seccomp" to "allow the io_uring syscalls in seccomp, restrict the operations
with `ioUring`".

### Prototype and evidence

- **youki prototype:** `dev.youki.io_uring` annotation with the same shape,
  applied in container init before seccomp. Link: TODO. It has 11 unit tests,
  and the end-to-end runs with real youki containers on 7.0 and 7.2.9 cover:
  - deny by default;
  - allow by default;
  - socket families;
  - deny-all;
  - SQE flags denied (`IOSQE_BUFFER_SELECT`, `IOSQE_FIXED_FILE`);
  - an invalid policy (refused);
  - inheritance by forked processes;
  - refusal on a kernel without support (6.18).
- **Lab:** 11 kernel-API scenarios in a VM, plus the youki scenarios and
  notes. Link: TODO.
- **Candidate default profile** with its rationale (opcode usage survey of 15 projects, io_uring CVE history): `profile/default.json`, `profile/RATIONALE.md`. Link: TODO.
- **liburing test:** a regression test for the exec case below. Link: TODO.

### Caveats and open questions

1. **Restrictions are lost on exec on 7.0 and 7.1.** If a restricted task has
   already used io_uring, its restrictions are dropped when it execs, so
   inside a container you can open a ring and exec anything.
   - CVE-2026-80713, fixed upstream in bc0e8faf90e7 (7.2), which is tagged for stable 7.1+.
     Ubuntu 26.04 has it in 7.0.0-39.
   - A version check can't tell a fixed distro kernel from an unfixed one.
     Should the spec require runtimes to self-test (restrict, use a ring,
     exec, check), or should it state a minimum kernel?
2. **Only rings created after registration are restricted.** A ring fd
   passed into the container (`SCM_RIGHTS`) is not restricted. This is
   probably fine to document, but worth stating.
3. **Few opcodes expose arguments to filters.** Only `SOCKET`,
   `OPENAT`/`OPENAT2` and, since 7.2, `CONNECT` do. Later fields could cover
   the `openat2` resolve flags and the `connect` families or ports. Is an
   extensible shape preferred now, e.g. `"rules": [{"op", "args"}]`?
4. **Register opcodes can't be filtered by BPF.** Only the one-shot
   allowlist covers them. Is restricting them needed for a default profile?

If this direction is acceptable, I'd send a PR for:

- `config-linux.md`;
- `schema/config-linux.json`;
- `features-linux.md`;
- `specs-go`.
