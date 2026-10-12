# io_uring: register restrictions skipped on disabled rings

Task-level io_uring register-op restrictions (7.0+) are skipped for rings
created with `IORING_SETUP_R_DISABLED`: a task restricted to only some register
opcodes can create a disabled ring, run any register opcode on it, then enable
it. No longer embargoed — the kernel side asked for a normal public patch, and
it is on the io-uring list.

Public write-up: [`../../FINDINGS.md`](../../FINDINGS.md),
[`../../profile/RATIONALE.md`](../../profile/RATIONALE.md).

## Status

- **2026-10-08** — private report sent (`security-report-final.txt`)
- **2026-10-09** — Jens Axboe: not a security issue, send a normal patch to
  `io-uring@vger.kernel.org`
- **2026-10-09** — patch v1 sent via B4 Relay:
  <https://lore.kernel.org/r/20261009-iouring-task-restrict-fix-v1-1-a49daf55a12c@gmail.com>
  (branch `iouring-task-restrict-fix` in `~/kwork/linux`, b4 prep, tag
  `sent/20261009-iouring-task-restrict-fix-e5f48783215e-v1`)
- **2026-10-09** — applied by Jens Axboe, commit
  `6da8f402e362b2f546e2efb7167fc9597aef6faf` (he folded in: set the inherited
  flag only with register restrictions); in mainline since v7.3-rc7

## Files

- `repro.c` — minimal C reproducer
- `run.sh` — builds `repro.c` and runs it unprivileged in the 7.0 and 7.2.9 VMs
  (artifacts go to `build/`, git-ignored)
- `regcheck/` — the first Rust check
- `patch-status.sh` — fetches the patch thread from lore with b4 and lists who replied
- `security-report.txt` — first draft of the private report
- `security-report-final.txt` — the report as sent
