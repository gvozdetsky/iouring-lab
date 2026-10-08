# iouring-lab

Making io_uring usable in containers, without turning security off.

Container engines block io_uring entirely, because seccomp can't see io_uring
operations. Linux 7.0 added task-level io_uring restrictions with classic BPF
filters per opcode, designed for containers and systemd. Nothing in the
container stack uses them yet. This repository holds the experiments and
evidence behind a proposal to change that.

| What | Where |
|---|---|
| Verified kernel behaviour, the youki prototype's results, open points | [FINDINGS.md](FINDINGS.md) |
| Candidate default profile and its rationale (usage survey of 15 projects, CVE history) | [profile/](profile/) |
| Proposal for an OCI runtime-spec `linux.ioUring` field | [proposals/runtime-spec-issue.md](proposals/runtime-spec-issue.md) |
| Probe tools: apply restrictions to a task, check which ops a ring may run | [probe/](probe/) |
| End-to-end runs with youki containers in a VM | [e2e/](e2e/) |
| youki prototype | draft PR [youki-dev/youki#3805](https://github.com/youki-dev/youki/pull/3805) (branch [`io-uring-restrictions`](https://github.com/gvozdetsky/youki/tree/io-uring-restrictions)) |

## Reproducing

Everything runs in WSL2 or on Linux with KVM:
- `virtme-ng` boots self-built kernels (7.0 and 7.2.9, see `build-7.0.sh`
  and `rebuild-kernel.sh` for the config);
- `probe/run-vm.sh <kernel tree> [guest script]` runs a script inside one.
- `probe/vm-tests.sh` covers the kernel API;
- `e2e/run.sh` runs youki containers with policies.

## License

Apache-2.0.
