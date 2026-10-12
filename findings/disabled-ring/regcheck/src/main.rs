//! Checks whether a task-level io_uring register-op allowlist (Linux 7.0+)
//! holds for rings created with IORING_SETUP_R_DISABLED, where
//! __io_uring_register() skipped the check. Fixed upstream in 6da8f402e362.
//!
//! The task allows only IORING_REGISTER_ENABLE_RINGS. Then:
//!   A. normal ring:   IORING_REGISTER_PROBE must be EACCES
//!   B. disabled ring: IORING_REGISTER_PROBE before enabling (bypass if 0)
//!   C. same ring after ENABLE_RINGS: IORING_REGISTER_PROBE must be EACCES

use std::io;

const IORING_SETUP_R_DISABLED: u32 = 1 << 6;
const IORING_REGISTER_PROBE: u32 = 8;
const IORING_REGISTER_RESTRICTIONS: u32 = 11;
const IORING_REGISTER_ENABLE_RINGS: u32 = 12;
const IORING_RESTRICTION_REGISTER_OP: u16 = 0;

fn setup(flags: u32) -> io::Result<i32> {
    // struct io_uring_params is 120 bytes; flags is the third u32.
    let mut params = [0u32; 30];
    params[2] = flags;
    let fd = unsafe { libc::syscall(libc::SYS_io_uring_setup, 4u32, params.as_mut_ptr()) };
    if fd < 0 { Err(io::Error::last_os_error()) } else { Ok(fd as i32) }
}

fn register(fd: i32, op: u32, arg: *mut libc::c_void, nr: u32) -> String {
    let r = unsafe { libc::syscall(libc::SYS_io_uring_register, fd, op, arg, nr) };
    if r < 0 { format!("{}", io::Error::last_os_error()) } else { format!("ok ({r})") }
}

fn probe(fd: i32) -> String {
    // struct io_uring_probe (16 bytes) + 256 * struct io_uring_probe_op (8 bytes)
    let mut buf = vec![0u8; 16 + 256 * 8];
    register(fd, IORING_REGISTER_PROBE, buf.as_mut_ptr().cast(), 256)
}

fn main() {
    if unsafe { libc::prctl(libc::PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) } != 0 {
        panic!("prctl");
    }
    // Header {flags u16, nr_res u16, resv [u32; 3]} + one restriction
    // {opcode u16, register_op u8, resv u8, resv2 [u32; 3]}.
    let mut arg = [0u8; 32];
    arg[2..4].copy_from_slice(&1u16.to_ne_bytes());
    arg[16..18].copy_from_slice(&IORING_RESTRICTION_REGISTER_OP.to_ne_bytes());
    arg[18] = IORING_REGISTER_ENABLE_RINGS as u8;
    println!("task allowlist {{ENABLE_RINGS}}: {}", register(-1, IORING_REGISTER_RESTRICTIONS, arg.as_mut_ptr().cast(), 1));

    let a = setup(0).expect("setup");
    println!("A. normal ring, REGISTER_PROBE:                 {}  (expected EACCES)", probe(a));

    let b = setup(IORING_SETUP_R_DISABLED).expect("setup disabled");
    println!("B. R_DISABLED ring, REGISTER_PROBE:             {}  (EACCES = enforced, ok = bypass)", probe(b));
    println!("   ENABLE_RINGS:                                {}", register(b, IORING_REGISTER_ENABLE_RINGS, std::ptr::null_mut(), 0));
    println!("C. same ring after enable, REGISTER_PROBE:      {}  (expected EACCES)", probe(b));
}
