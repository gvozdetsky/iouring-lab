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

## Open points

- youki rootless mode needs systemd for cgroups, so the full rootless
  container run needs a host with systemd and a 7.x kernel.
- Restrictions persist across exec only since 7.2 (bc0e8faf) for tasks that
  already used io_uring; check 7.0 (Ubuntu 26.04 LTS).
- Only rings created after registration are restricted: a ring fd passed in
  from outside the container is not. Document in the proposal.
