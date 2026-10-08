//! iou-restrict: apply task-level io_uring restrictions (Linux 7.0+) to the
//! current process, then exec a command under them.
//!
//! Usage:
//!   iou-restrict [--nnp] [--ops N,N,..] [--sqe-flags MASK]
//!                [--bpf-allow N,N,..] [--socket-families F,F,..] -- CMD [ARGS..]
//!
//! --ops        task opcode allowlist (IORING_REGISTER_RESTRICTIONS, fd = -1).
//!              Can be registered once per task, and must come before any BPF filter.
//! --sqe-flags  IOSQE_* flags allowed together with --ops (default 0 = none).
//! --bpf-allow  allowlist built only from cBPF filters: an allow-all filter per
//!              listed opcode, then IO_URING_BPF_FILTER_DENY_REST for the rest.
//!              Unlike --ops it stacks: later filters can still be added.
//! --socket-families  cBPF filter on IORING_OP_SOCKET allowing only these
//!              address families (e.g. 1=AF_UNIX, 2=AF_INET, 10=AF_INET6).
//! --nnp        set PR_SET_NO_NEW_PRIVS first (required without CAP_SYS_ADMIN).
//! --use-ring   create (and drop) an io_uring before exec.

use std::ffi::CString;
use std::io;

const IORING_REGISTER_RESTRICTIONS: libc::c_uint = 11;
const IORING_REGISTER_BPF_FILTER: libc::c_uint = 37;

const IORING_RESTRICTION_SQE_OP: u16 = 1;
const IORING_RESTRICTION_SQE_FLAGS_ALLOWED: u16 = 2;

const IORING_OP_SOCKET: u32 = 45;

const IO_URING_BPF_CMD_FILTER: u16 = 1;
const IO_URING_BPF_FILTER_DENY_REST: u32 = 1;

// Classic BPF opcodes (linux/filter.h).
const BPF_LD: u16 = 0x00;
const BPF_W: u16 = 0x00;
const BPF_ABS: u16 = 0x20;
const BPF_JMP: u16 = 0x05;
const BPF_JEQ: u16 = 0x10;
const BPF_K: u16 = 0x00;
const BPF_RET: u16 = 0x06;

/// Offset of the per-opcode union in `struct io_uring_bpf_ctx`.
const CTX_PDU_OFFSET: u32 = 16;

#[repr(C)]
struct IoUringRestriction {
    opcode: u16,
    op: u8, // register_op / sqe_op / sqe_flags
    resv: u8,
    resv2: [u32; 3],
}

#[repr(C)]
struct IoUringTaskRestrictionHeader {
    flags: u16,
    nr_res: u16,
    resv: [u32; 3],
}

#[repr(C)]
struct IoUringBpfFilter {
    opcode: u32,
    flags: u32,
    filter_len: u32,
    pdu_size: u8,
    resv: [u8; 3],
    filter_ptr: u64,
    resv2: [u64; 5],
}

#[repr(C)]
struct IoUringBpf {
    cmd_type: u16,
    cmd_flags: u16,
    resv: u32,
    filter: IoUringBpfFilter,
}

const _: () = assert!(std::mem::size_of::<IoUringRestriction>() == 16);
const _: () = assert!(std::mem::size_of::<IoUringTaskRestrictionHeader>() == 16);
const _: () = assert!(std::mem::size_of::<IoUringBpfFilter>() == 64);
const _: () = assert!(std::mem::size_of::<IoUringBpf>() == 72);

fn register_task(opcode: libc::c_uint, arg: *const libc::c_void) -> io::Result<()> {
    // fd = -1 selects the task-level ("blind") registration path.
    let ret = unsafe { libc::syscall(libc::SYS_io_uring_register, -1i32, opcode, arg, 1u32) };
    if ret < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

fn register_ops_allowlist(ops: &[u8], sqe_flags: u8) -> io::Result<()> {
    let mut entries: Vec<IoUringRestriction> = ops
        .iter()
        .map(|&op| IoUringRestriction { opcode: IORING_RESTRICTION_SQE_OP, op, resv: 0, resv2: [0; 3] })
        .collect();
    entries.push(IoUringRestriction {
        opcode: IORING_RESTRICTION_SQE_FLAGS_ALLOWED,
        op: sqe_flags,
        resv: 0,
        resv2: [0; 3],
    });
    let header = IoUringTaskRestrictionHeader { flags: 0, nr_res: entries.len() as u16, resv: [0; 3] };
    let mut buf = Vec::with_capacity(16 * (entries.len() + 1));
    buf.extend_from_slice(as_bytes(&header));
    for e in &entries {
        buf.extend_from_slice(as_bytes(e));
    }
    register_task(IORING_REGISTER_RESTRICTIONS, buf.as_ptr().cast())
}

fn register_bpf(opcode: u32, flags: u32, prog: &[libc::sock_filter]) -> io::Result<()> {
    let bpf = IoUringBpf {
        cmd_type: IO_URING_BPF_CMD_FILTER,
        cmd_flags: 0,
        resv: 0,
        filter: IoUringBpfFilter {
            opcode,
            flags,
            filter_len: prog.len() as u32,
            pdu_size: 0,
            resv: [0; 3],
            filter_ptr: prog.as_ptr() as u64,
            resv2: [0; 5],
        },
    };
    register_task(IORING_REGISTER_BPF_FILTER, (&bpf as *const IoUringBpf).cast())
}

fn stmt(code: u16, k: u32) -> libc::sock_filter {
    libc::sock_filter { code, jt: 0, jf: 0, k }
}

fn jump(code: u16, k: u32, jt: u8, jf: u8) -> libc::sock_filter {
    libc::sock_filter { code, jt, jf, k }
}

fn allow_all() -> Vec<libc::sock_filter> {
    vec![stmt(BPF_RET | BPF_K, 1)]
}

/// Allow IORING_OP_SOCKET only for the given address families.
fn socket_family_filter(families: &[u32]) -> Vec<libc::sock_filter> {
    let n = families.len();
    let mut prog = vec![stmt(BPF_LD | BPF_W | BPF_ABS, CTX_PDU_OFFSET)];
    for (i, &family) in families.iter().enumerate() {
        // Jump to the trailing "allow" on a match.
        prog.push(jump(BPF_JMP | BPF_JEQ | BPF_K, family, (n - i) as u8, 0));
    }
    prog.push(stmt(BPF_RET | BPF_K, 0));
    prog.push(stmt(BPF_RET | BPF_K, 1));
    prog
}

fn as_bytes<T>(v: &T) -> &[u8] {
    unsafe { std::slice::from_raw_parts((v as *const T).cast(), std::mem::size_of::<T>()) }
}

fn parse_list(s: &str) -> Vec<u32> {
    s.split(',').filter(|x| !x.is_empty()).map(|x| x.trim().parse().expect("number")).collect()
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let sep = args.iter().position(|a| a == "--").expect("missing -- CMD");
    let (opts, cmd) = (&args[1..sep], &args[sep + 1..]);
    assert!(!cmd.is_empty(), "missing command after --");

    let (mut nnp, mut ops, mut sqe_flags, mut bpf_allow, mut families) = (false, None, 0u8, None, None);
    let mut use_ring = false;
    let mut it = opts.iter();
    while let Some(o) = it.next() {
        match o.as_str() {
            "--nnp" => nnp = true,
            "--use-ring" => use_ring = true,
            "--ops" => ops = Some(parse_list(it.next().expect("--ops value"))),
            "--sqe-flags" => sqe_flags = it.next().expect("--sqe-flags value").parse().expect("mask"),
            "--bpf-allow" => bpf_allow = Some(parse_list(it.next().expect("--bpf-allow value"))),
            "--socket-families" => families = Some(parse_list(it.next().expect("--socket-families value"))),
            other => panic!("unknown option {other}"),
        }
    }

    if nnp && unsafe { libc::prctl(libc::PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) } != 0 {
        eprintln!("prctl(NO_NEW_PRIVS): {}", io::Error::last_os_error());
        std::process::exit(1);
    }
    // The opcode allowlist has to be registered before any BPF filter:
    // once the task has restrictions, IORING_REGISTER_RESTRICTIONS is EPERM.
    if let Some(ops) = &ops {
        let ops: Vec<u8> = ops.iter().map(|&o| o as u8).collect();
        match register_ops_allowlist(&ops, sqe_flags) {
            Ok(()) => eprintln!("iou-restrict: ops allowlist {ops:?}, sqe flags {sqe_flags:#x}"),
            Err(e) => fail("ops allowlist", e),
        }
    }
    if let Some(families) = &families {
        match register_bpf(IORING_OP_SOCKET, 0, &socket_family_filter(families)) {
            Ok(()) => eprintln!("iou-restrict: socket families {families:?}"),
            Err(e) => fail("socket filter", e),
        }
    }
    if let Some(allow) = &bpf_allow {
        for (i, &op) in allow.iter().enumerate() {
            // The last registration also fills every opcode without a filter
            // with a deny stub.
            let flags = if i + 1 == allow.len() { IO_URING_BPF_FILTER_DENY_REST } else { 0 };
            if let Err(e) = register_bpf(op, flags, &allow_all()) {
                fail(&format!("bpf allow op {op}"), e);
            }
        }
        eprintln!("iou-restrict: bpf allowlist {allow:?} + DENY_REST");
    }

    // Use io_uring in this task before exec (gives it an io_uring task
    // context): before 7.2, such a task dropped its restrictions on exec.
    if use_ring {
        let ring = io_uring::IoUring::new(4).unwrap_or_else(|e| fail("io_uring_setup", e));
        drop(ring);
        eprintln!("iou-restrict: used a ring before exec");
    }

    let prog = CString::new(cmd[0].as_str()).unwrap();
    let argv: Vec<CString> = cmd.iter().map(|a| CString::new(a.as_str()).unwrap()).collect();
    let mut argv_ptrs: Vec<*const libc::c_char> = argv.iter().map(|a| a.as_ptr()).collect();
    argv_ptrs.push(std::ptr::null());
    unsafe { libc::execvp(prog.as_ptr(), argv_ptrs.as_ptr()) };
    fail("execvp", io::Error::last_os_error());
}

fn fail(what: &str, e: io::Error) -> ! {
    eprintln!("iou-restrict: {what}: {e}");
    std::process::exit(1);
}
