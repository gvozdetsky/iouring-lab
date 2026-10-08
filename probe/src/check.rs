//! iou-check: try a set of io_uring operations on a fresh ring and report
//! which ones the kernel allows. `--fork` repeats the checks in a child.

use io_uring::{opcode, squeue, types, IoUring};
use std::ffi::CString;
use std::io;

fn run(ring: &mut IoUring, entries: &[squeue::Entry]) -> Vec<i32> {
    for e in entries {
        unsafe { ring.submission().push(e).expect("sq full") };
    }
    ring.submit_and_wait(entries.len()).expect("submit");
    let mut res: Vec<(u64, i32)> = ring.completion().map(|c| (c.user_data(), c.result())).collect();
    res.sort();
    res.into_iter().map(|(_, r)| r).collect()
}

fn show(name: &str, res: i32) {
    let verdict = if res >= 0 {
        format!("ok ({res})")
    } else {
        let e = io::Error::from_raw_os_error(-res);
        if -res == libc::EACCES {
            "DENIED (EACCES)".to_string()
        } else {
            format!("error: {e}")
        }
    };
    println!("  {name:<28} {verdict}");
    if res > 2 && (name.starts_with("socket") || name.starts_with("openat")) {
        unsafe { libc::close(res) };
    }
}

fn checks(label: &str) {
    println!("[{label}] pid {}", std::process::id());
    let mut ring = match IoUring::new(8) {
        Ok(r) => r,
        Err(e) => {
            println!("  {:<28} error: {e}", "io_uring_setup");
            return;
        }
    };
    println!("  {:<28} ok", "io_uring_setup");

    let path = CString::new("/etc/hostname").unwrap();
    let single: Vec<(&str, squeue::Entry)> = vec![
        ("nop", opcode::Nop::new().build()),
        ("socket AF_INET stream", opcode::Socket::new(libc::AF_INET, libc::SOCK_STREAM, 0).build()),
        ("socket AF_UNIX stream", opcode::Socket::new(libc::AF_UNIX, libc::SOCK_STREAM, 0).build()),
        ("socket AF_NETLINK raw", opcode::Socket::new(libc::AF_NETLINK, libc::SOCK_RAW, 0).build()),
        (
            "openat /etc/hostname",
            opcode::OpenAt::new(types::Fd(libc::AT_FDCWD), path.as_ptr()).flags(libc::O_RDONLY).build(),
        ),
    ];
    for (i, (name, e)) in single.into_iter().enumerate() {
        let r = run(&mut ring, &[e.user_data(i as u64)]);
        show(name, r[0]);
    }
    // A read with provided-buffer selection but no buffers registered: the
    // kernel answers ENOBUFS when allowed, EACCES when a filter denies it.
    let file = std::fs::File::open("/etc/hostname").expect("open /etc/hostname");
    let fd = std::os::fd::AsRawFd::as_raw_fd(&file);
    let r = run(
        &mut ring,
        &[opcode::Read::new(types::Fd(fd), std::ptr::null_mut(), 64)
            .buf_group(0)
            .build()
            .flags(squeue::Flags::BUFFER_SELECT)
            .user_data(200)],
    );
    show("read + BUFFER_SELECT", r[0]);
    // A read on fixed file 0 with no file table: EBADF when allowed.
    let r = run(
        &mut ring,
        &[opcode::Read::new(types::Fixed(0), std::ptr::null_mut(), 0).build().user_data(201)],
    );
    show("read + FIXED_FILE", r[0]);
    // Two NOPs linked with IOSQE_IO_LINK: exercises the SQE-flags restriction.
    let r = run(
        &mut ring,
        &[
            opcode::Nop::new().build().flags(squeue::Flags::IO_LINK).user_data(100),
            opcode::Nop::new().build().user_data(101),
        ],
    );
    show("nop + IO_LINK", r[0]);
}

fn main() {
    let fork = std::env::args().any(|a| a == "--fork");
    checks("parent");
    if fork {
        match unsafe { libc::fork() } {
            0 => {
                checks("forked child");
                std::process::exit(0);
            }
            pid if pid > 0 => {
                let mut status = 0;
                unsafe { libc::waitpid(pid, &mut status, 0) };
            }
            _ => eprintln!("fork: {}", io::Error::last_os_error()),
        }
    }
}
