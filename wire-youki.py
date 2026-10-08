#!/usr/bin/env python3
"""Wire the io_uring module into youki's libcontainer (idempotent)."""
import pathlib, sys

src = pathlib.Path.home() / "iouring-lab/youki/crates/libcontainer/src"

def edit(rel, old, new):
    p = src / rel
    text = p.read_text()
    if new in text:
        print(f"{rel}: already done")
        return
    if text.count(old) != 1:
        sys.exit(f"{rel}: anchor found {text.count(old)} times")
    p.write_text(text.replace(old, new))
    print(f"{rel}: edited")

edit("lib.rs", "pub mod hooks;\n", "pub mod hooks;\npub mod io_uring;\n")

edit("error.rs",
     "    #[error(\"runtime spec has incompatible version. Only 1.X.Y is supported\")]\n    UnsupportedVersion,\n",
     "    #[error(\"runtime spec has incompatible version. Only 1.X.Y is supported\")]\n    UnsupportedVersion,\n"
     "    #[error(transparent)]\n    IoUring(#[from] crate::io_uring::IoUringError),\n")

edit("process/init/error.rs",
     "    #[error(\"invalid executable: {0}\")]\n",
     "    #[error(transparent)]\n    IoUring(#[from] crate::io_uring::IoUringError),\n    #[error(\"invalid executable: {0}\")]\n")

edit("process/init/process.rs",
     "    // Without no new privileges, seccomp is a privileged operation. We have to\n",
     "    // io_uring restrictions (experimental, dev.youki.io_uring annotation) go\n"
     "    // before seccomp, which may deny io_uring_register, and before\n"
     "    // capabilities are dropped: like seccomp, registering them needs\n"
     "    // CAP_SYS_ADMIN in the user namespace or no_new_privs.\n"
     "    if let Some(policy) = io_uring::policy_from_spec(ctx.spec)? {\n"
     "        io_uring::apply(&policy).map_err(|err| {\n"
     "            tracing::error!(?err, \"failed to apply io_uring restrictions\");\n"
     "            err\n"
     "        })?;\n"
     "    }\n\n"
     "    // Without no new privileges, seccomp is a privileged operation. We have to\n")

edit("process/init/process.rs",
     "use crate::{apparmor, capabilities, hooks, tty, utils};\n",
     "use crate::{apparmor, capabilities, hooks, io_uring, tty, utils};\n")

edit("validator.rs",
     "        Self::validate_spec_for_new_user_ns(spec, is_rootless)?;\n",
     "        Self::validate_spec_for_new_user_ns(spec, is_rootless)?;\n"
     "        Self::validate_spec_for_io_uring(spec)?;\n")

edit("validator.rs",
     "impl Validator {\n",
     "impl Validator {\n"
     "    // A container with an io_uring policy must not start on a kernel that\n"
     "    // can't enforce it: fail here, before anything is created.\n"
     "    fn validate_spec_for_io_uring(spec: &Spec) -> Result<(), ErrInvalidSpec> {\n"
     "        if crate::io_uring::policy_from_spec(spec)?.is_some() && !crate::io_uring::supported() {\n"
     "            return Err(crate::io_uring::IoUringError::Unsupported.into());\n"
     "        }\n"
     "        Ok(())\n"
     "    }\n\n")
