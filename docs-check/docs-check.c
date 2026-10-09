// SPDX-License-Identifier: MIT
/*
 * Checks the claims of a man page update for io_uring_register_bpf_filter(3)
 * on a real kernel, using liburing with the updated bpf_filter.h:
 *   1. the kernel's pdu_size for IORING_OP_CONNECT (EMSGSIZE write-back)
 *   2. a filter can test sqe_flags by loading the word at offset 8 and
 *      masking it (the man page example "Deny provided buffer selection")
 *   3. task filters make task IORING_REGISTER_RESTRICTIONS fail with EPERM
 */
#include <endian.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <linux/filter.h>
#include <liburing.h>
#include <liburing/io_uring/bpf_filter.h>

#if __BYTE_ORDER == __LITTLE_ENDIAN
#define SQE_FLAGS_SHIFT	8
#else
#define SQE_FLAGS_SHIFT	16
#endif

static int connect_pdu_size(void)
{
	struct io_uring ring;
	struct sock_filter allow[] = { BPF_STMT(BPF_RET | BPF_K, 1) };
	struct io_uring_bpf bpf = {
		.cmd_type = IO_URING_BPF_CMD_FILTER,
		.filter = {
			.opcode = IORING_OP_CONNECT,
			.flags = IO_URING_BPF_FILTER_SZ_STRICT,
			.filter_len = 1,
			.filter_ptr = (unsigned long) allow,
			.pdu_size = 0,
		},
	};
	int ret;

	if (io_uring_queue_init(4, &ring, 0))
		return -1;
	ret = io_uring_register_bpf_filter(&ring, &bpf);
	printf("1. CONNECT, pdu_size 0, SZ_STRICT: ret=%d, kernel pdu_size=%u\n",
	       ret, bpf.filter.pdu_size);
	io_uring_queue_exit(&ring);
	return 0;
}

static int read_with(struct io_uring *ring, int fd, int buffer_select)
{
	struct io_uring_sqe *sqe = io_uring_get_sqe(ring);
	struct io_uring_cqe *cqe;
	int res;

	io_uring_prep_read(sqe, fd, NULL, buffer_select ? 64 : 0, 0);
	if (buffer_select) {
		sqe->flags |= IOSQE_BUFFER_SELECT;
		sqe->buf_group = 0;
	}
	io_uring_submit(ring);
	io_uring_wait_cqe(ring, &cqe);
	res = cqe->res;
	io_uring_cqe_seen(ring, cqe);
	return res;
}

static void deny_buffer_select(void)
{
	/* The man page example, verbatim apart from the surrounding code */
	struct sock_filter no_buffer_select[] = {
		/* Load the word holding opcode, sqe_flags and pdu_size */
		BPF_STMT(BPF_LD | BPF_W | BPF_ABS, 8),
		/* If IOSQE_BUFFER_SELECT is set, deny */
		BPF_JUMP(BPF_JMP | BPF_JSET | BPF_K,
			 IOSQE_BUFFER_SELECT << SQE_FLAGS_SHIFT, 0, 1),
		BPF_STMT(BPF_RET | BPF_K, 0),
		BPF_STMT(BPF_RET | BPF_K, 1),
	};
	struct io_uring_bpf bpf = {
		.cmd_type = IO_URING_BPF_CMD_FILTER,
		.filter = {
			.opcode = IORING_OP_READ,
			.filter_len = 4,
			.filter_ptr = (unsigned long) no_buffer_select,
		},
	};
	struct io_uring ring;
	int fd = open("/etc/hostname", O_RDONLY);

	if (io_uring_queue_init(4, &ring, 0) || fd < 0)
		return;
	printf("2. before filter: read=%d, read+BUFFER_SELECT=%d (ENOBUFS=%d)\n",
	       read_with(&ring, fd, 0), read_with(&ring, fd, 1), -ENOBUFS);
	printf("   register: %d\n", io_uring_register_bpf_filter(&ring, &bpf));
	printf("   after filter: read=%d, read+BUFFER_SELECT=%d (EACCES=%d)\n",
	       read_with(&ring, fd, 0), read_with(&ring, fd, 1), -EACCES);
	io_uring_queue_exit(&ring);
	close(fd);
}

static void ordering(void)
{
	pid_t pid = fork();

	if (pid == 0) {
		struct sock_filter allow[] = { BPF_STMT(BPF_RET | BPF_K, 1) };
		struct io_uring_bpf bpf = {
			.cmd_type = IO_URING_BPF_CMD_FILTER,
			.filter = {
				.opcode = IORING_OP_NOP,
				.filter_len = 1,
				.filter_ptr = (unsigned long) allow,
			},
		};
		struct {
			__u16 flags, nr_res;
			__u32 resv[3];
			struct io_uring_restriction res[1];
		} tr = { .nr_res = 1, .res[0] = {
			.opcode = IORING_RESTRICTION_SQE_OP,
			.sqe_op = IORING_OP_NOP } };
		long ret;

		prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
		printf("3. task BPF filter: %d\n", io_uring_register_bpf_filter_task(&bpf));
		ret = syscall(__NR_io_uring_register, -1, IORING_REGISTER_RESTRICTIONS, &tr, 1);
		printf("   then task IORING_REGISTER_RESTRICTIONS: %ld (%s)\n",
		       ret, ret < 0 ? strerror(errno) : "ok");
		fflush(stdout);
		_exit(0);
	}
	waitpid(pid, NULL, 0);
}

int main(void)
{
	setvbuf(stdout, NULL, _IOLBF, 0);
	connect_pdu_size();
	deny_buffer_select();
	ordering();
	return 0;
}
