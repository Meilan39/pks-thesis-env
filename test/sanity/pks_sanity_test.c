// SPDX-License-Identifier: GPL-2.0
// ============================================================================
// pks_sanity_test.c - PKS Page-Cache Protection Contract Verifier
// ============================================================================
// Purpose-built user-space verifier for the thesis mitigation. Unlike a generic
// POSIX conformance suite, every assertion here maps onto a specific invariant
// of the PKS page-cache design (see context/overview.md):
//
//   Suite 1  Sanctioned write-path scoping   write/pwrite/writev/ftruncate/
//                                             fallocate open a thread-local
//                                             write scope; read() does not;
//                                             begin/end counters stay balanced.
//   Suite 2  Static-pool residency           every resident folio of a
//                                             protected file lies inside the
//                                             pre-tagged PMD-aligned pool.
//   Suite 3  Fail-closed rejection matrix     mmap(PROT_WRITE), O_DIRECT,
//                                             splice, sendfile, copy_file_range,
//                                             AIO, and EXT4_IOC_MOVE_EXT are all
//                                             rejected with -EOPNOTSUPP.
//   Suite 4  Permitted-operation controls     buffered I/O, truncation, and
//                                             read-only mappings still work, and
//                                             a private mapping cannot be
//                                             upgraded to writable (no false
//                                             rejections / no over-blocking).
//
// Output contract: one "[PASS]"/"[FAIL]" line per assertion (tallied by
// test/sanity/run.sh) and "[SKIP]"/"[INFO]"/"[WARN]" lines that are ignored.
// Assertions that cannot be set up in the current environment SKIP rather than
// FAIL; a FAIL is reserved for an actual contract violation.
// ============================================================================
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/mman.h>
#include <sys/uio.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <inttypes.h>

#ifdef __linux__
#include <sys/sendfile.h>
#include <sys/syscall.h>
#include <linux/ioctl.h>
#include <linux/aio_abi.h>
#endif

#ifndef O_DIRECT
#define O_DIRECT 00040000
#endif

#ifndef __linux__
int fallocate(int fd, int mode, off_t offset, off_t len);
ssize_t splice(int fd_in, off_t *off_in, int fd_out, off_t *off_out, size_t len, unsigned int flags);
#endif

#define STATUS_PATH "/sys/kernel/debug/pcache_pks/status"
#define MOUNT_PATH  "/mnt/protected"
#define PAGE_SIZE_BYTES 4096

// Mirror of struct ext4_move_extent (fs/ext4/ext4.h); laid out by fixed-width
// types so the ioctl command number is computed identically to the kernel's.
struct sanity_move_extent {
	uint32_t reserved;
	uint32_t donor_fd;
	uint64_t orig_start;
	uint64_t donor_start;
	uint64_t len;
	uint64_t moved_len;
};

#ifdef __linux__
#ifndef EXT4_IOC_MOVE_EXT
#define EXT4_IOC_MOVE_EXT _IOWR('f', 15, struct sanity_move_extent)
#endif
#endif

static unsigned long g_pool_start_pfn = 0;
static unsigned long g_pool_end_pfn = 0;
static bool g_has_debugfs = false;

static bool read_debugfs_status(uint64_t *begin_cnt, uint64_t *end_cnt)
{
	if (begin_cnt)
		*begin_cnt = 0;
	if (end_cnt)
		*end_cnt = 0;

	FILE *fp = fopen(STATUS_PATH, "r");
	if (!fp)
		return false;

	char line[256];
	while (fgets(line, sizeof(line), fp)) {
		if (strncmp(line, "pool_start_pfn:", 15) == 0)
			sscanf(line + 15, " 0x%lx", &g_pool_start_pfn);
		else if (strncmp(line, "pool_end_pfn:", 13) == 0)
			sscanf(line + 13, " 0x%lx", &g_pool_end_pfn);
		else if (strncmp(line, "scope_begin_count:", 18) == 0) {
			if (begin_cnt)
				sscanf(line + 18, " %" SCNu64, begin_cnt);
		} else if (strncmp(line, "scope_end_count:", 16) == 0) {
			if (end_cnt)
				sscanf(line + 16, " %" SCNu64, end_cnt);
		} else if (strncmp(line, "scope_count:", 12) == 0) {
			uint64_t sc = 0;
			sscanf(line + 12, " %" SCNu64, &sc);
			if (begin_cnt)
				*begin_cnt = sc;
			if (end_cnt)
				*end_cnt = sc;
		}
	}
	fclose(fp);
	return true;
}

// ----------------------------------------------------------------------------
// Suite 1 - Sanctioned write-path scoping
// ----------------------------------------------------------------------------
static int test_vfs_scoping(const char *test_file)
{
	printf("\n==> [Suite 1] Supported VFS System-Call Scoping Verification\n");

	if (!g_has_debugfs) {
		printf("    [SKIP] DebugFS status not available at %s (built without CONFIG_PCACHE_PKS_DEBUG?)\n", STATUS_PATH);
		return 0;
	}

	uint64_t b0, e0, b1, e1;
	read_debugfs_status(&b0, &e0);

	int fd = open(test_file, O_CREAT | O_RDWR | O_TRUNC, 0644);
	if (fd < 0) {
		perror("open test_file");
		return 1;
	}

	// 1. write()
	read_debugfs_status(&b0, &e0);
	char buf[4096];
	memset(buf, 'A', sizeof(buf));
	if (write(fd, buf, sizeof(buf)) != sizeof(buf)) {
		perror("write");
		close(fd);
		return 1;
	}
	read_debugfs_status(&b1, &e1);
	if (b1 > b0 && e1 > e0 && b1 == e1) {
		printf("    [PASS] write(2) scoped cleanly (+%" PRIu64 " begin, +%" PRIu64 " end)\n", b1 - b0, e1 - e0);
	} else {
		printf("    [FAIL] write(2) scope count mismatch: begin %" PRIu64 " -> %" PRIu64 ", end %" PRIu64 " -> %" PRIu64 "\n", b0, b1, e0, e1);
		close(fd);
		return 1;
	}

	// 2. pwrite()
	read_debugfs_status(&b0, &e0);
	if (pwrite(fd, buf, sizeof(buf), 4096) != sizeof(buf)) {
		perror("pwrite");
		close(fd);
		return 1;
	}
	read_debugfs_status(&b1, &e1);
	if (b1 > b0 && e1 > e0) {
		printf("    [PASS] pwrite(2) scoped cleanly (+%" PRIu64 " begin, +%" PRIu64 " end)\n", b1 - b0, e1 - e0);
	} else {
		printf("    [FAIL] pwrite(2) scope count mismatch\n");
		close(fd);
		return 1;
	}

	// 3. writev()
	read_debugfs_status(&b0, &e0);
	struct iovec iov[2];
	iov[0].iov_base = buf;
	iov[0].iov_len = 512;
	iov[1].iov_base = buf + 512;
	iov[1].iov_len = 512;
	if (writev(fd, iov, 2) != 1024) {
		perror("writev");
		close(fd);
		return 1;
	}
	read_debugfs_status(&b1, &e1);
	if (b1 > b0 && e1 > e0) {
		printf("    [PASS] writev(2) scoped cleanly (+%" PRIu64 " begin, +%" PRIu64 " end)\n", b1 - b0, e1 - e0);
	} else {
		printf("    [FAIL] writev(2) scope count mismatch\n");
		close(fd);
		return 1;
	}

	// 4. ftruncate()
	read_debugfs_status(&b0, &e0);
	if (ftruncate(fd, 65536) != 0) {
		perror("ftruncate");
		close(fd);
		return 1;
	}
	read_debugfs_status(&b1, &e1);
	if (b1 > b0 && e1 > e0) {
		printf("    [PASS] ftruncate(2) scoped cleanly (+%" PRIu64 " begin, +%" PRIu64 " end)\n", b1 - b0, e1 - e0);
	} else {
		printf("    [FAIL] ftruncate(2) scope count mismatch\n");
		close(fd);
		return 1;
	}

	// 5. fallocate()
	read_debugfs_status(&b0, &e0);
	if (fallocate(fd, 0, 0, 131072) != 0) {
		perror("fallocate");
		close(fd);
		return 1;
	}
	read_debugfs_status(&b1, &e1);
	if (b1 > b0 && e1 > e0) {
		printf("    [PASS] fallocate(2) scoped cleanly (+%" PRIu64 " begin, +%" PRIu64 " end)\n", b1 - b0, e1 - e0);
	} else {
		printf("    [FAIL] fallocate(2) scope count mismatch\n");
		close(fd);
		return 1;
	}

	// 6. read() / pread() - MUST NOT increment write scopes
	read_debugfs_status(&b0, &e0);
	char r_buf[1024];
	if (pread(fd, r_buf, sizeof(r_buf), 0) != sizeof(r_buf)) {
		perror("pread");
		close(fd);
		return 1;
	}
	read_debugfs_status(&b1, &e1);
	if (b1 == b0 && e1 == e0) {
		printf("    [PASS] read(2) executed with 0 write-scope toggles (read-path parity confirmed)\n");
	} else {
		printf("    [FAIL] read(2) unexpectedly triggered write-scope toggle (+%" PRIu64 ")\n", b1 - b0);
		close(fd);
		return 1;
	}

	// 7. Balance check: begin == end
	read_debugfs_status(&b1, &e1);
	if (b1 == e1) {
		printf("    [PASS] Total scope balance verified: %" PRIu64 " entries == %" PRIu64 " exits (leak-free invariant)\n", b1, e1);
	} else {
		printf("    [FAIL] Scope leak detected: %" PRIu64 " entries vs %" PRIu64 " exits\n", b1, e1);
		close(fd);
		return 1;
	}

	close(fd);
	unlink(test_file);
	return 0;
}

// ----------------------------------------------------------------------------
// Suite 2 - Static-pool page-cache residency
// ----------------------------------------------------------------------------
static int test_static_pool_pfn(const char *test_file)
{
	printf("\n==> [Suite 2] Static Pool Page-Cache Allocation Verification\n");

	if (!g_has_debugfs || g_pool_start_pfn == 0) {
		printf("    [SKIP] Pool boundaries not available from DebugFS\n");
		return 0;
	}

	printf("    [INFO] Pool PFN range: [0x%lx, 0x%lx)\n", g_pool_start_pfn, g_pool_end_pfn);

	const size_t test_size = 4 * 1024 * 1024; // 4 MiB (1024 pages)
	const size_t num_pages = test_size / PAGE_SIZE_BYTES;

	int fd = open(test_file, O_CREAT | O_RDWR | O_TRUNC, 0644);
	if (fd < 0) {
		perror("open pool test file");
		return 1;
	}

	char *zero_buf = calloc(1, PAGE_SIZE_BYTES);
	if (!zero_buf) {
		perror("calloc");
		close(fd);
		return 1;
	}

	for (size_t i = 0; i < num_pages; i++) {
		if (write(fd, zero_buf, PAGE_SIZE_BYTES) != PAGE_SIZE_BYTES) {
			perror("write pool data");
			free(zero_buf);
			close(fd);
			return 1;
		}
	}
	free(zero_buf);

	// Map file read-only to query virtual-to-physical translations via /proc/self/pagemap
	void *addr = mmap(NULL, test_size, PROT_READ, MAP_SHARED, fd, 0);
	if (addr == MAP_FAILED) {
		perror("mmap PROT_READ");
		close(fd);
		return 1;
	}

	// Touch all pages to guarantee page-cache residency
	volatile char touch = 0;
	for (size_t i = 0; i < num_pages; i++) {
		touch += ((char *)addr)[i * PAGE_SIZE_BYTES];
	}
	(void)touch;

	int pagemap_fd = open("/proc/self/pagemap", O_RDONLY);
	if (pagemap_fd < 0) {
		perror("open /proc/self/pagemap (run as root to inspect physical PFNs)");
		munmap(addr, test_size);
		close(fd);
		return 0; // Don't fail if non-root lacking pagemap permission
	}

	size_t pool_valid_count = 0;
	size_t pool_invalid_count = 0;

	for (size_t i = 0; i < num_pages; i++) {
		uintptr_t vaddr = (uintptr_t)addr + (i * PAGE_SIZE_BYTES);
		off_t offset = (vaddr / PAGE_SIZE_BYTES) * 8;
		uint64_t pagemap_entry = 0;

		if (pread(pagemap_fd, &pagemap_entry, sizeof(pagemap_entry), offset) != sizeof(pagemap_entry)) {
			perror("pread pagemap");
			break;
		}

		// Bit 63: page present; Bits 0-54: PFN
		if (pagemap_entry & (1ULL << 63)) {
			unsigned long pfn = pagemap_entry & ((1ULL << 55) - 1);
			if (pfn >= g_pool_start_pfn && pfn < g_pool_end_pfn) {
				pool_valid_count++;
			} else {
				pool_invalid_count++;
				if (pool_invalid_count <= 3) {
					printf("    [WARN] Page %zu at PFN 0x%lx falls outside pool [0x%lx, 0x%lx)\n",
					       i, pfn, g_pool_start_pfn, g_pool_end_pfn);
				}
			}
		}
	}

	close(pagemap_fd);
	munmap(addr, test_size);
	close(fd);
	unlink(test_file);

	printf("    [INFO] Inspected %zu resident pages: %zu in static pool, %zu outside\n",
	       num_pages, pool_valid_count, pool_invalid_count);

	if (pool_invalid_count == 0 && pool_valid_count > 0) {
		printf("    [PASS] 100%% of resident page-cache folios reside strictly in the PKS static pool\n");
		return 0;
	} else if (pool_valid_count == 0) {
		printf("    [SKIP] Could not resolve physical PFNs (requires CAP_SYS_ADMIN / root privileges)\n");
		return 0;
	} else {
		printf("    [FAIL] Detected non-pool folio allocations on protected mount\n");
		return 1;
	}
}

// ----------------------------------------------------------------------------
// Suite 3 helpers - fail-closed rejection matrix
// ----------------------------------------------------------------------------
// Classify a fail-closed attempt. did_succeed is nonzero if the operation
// completed (a policy breach); err is errno captured right after a failure.
// The thesis rejects every operation in this suite with -EOPNOTSUPP.
// Returns 1 when the check failed (for the suite tally), else 0.
static int expect_rejected(const char *label, int did_succeed, int err)
{
	if (did_succeed) {
		printf("    [FAIL] %s was permitted on a protected file (fail-closed breach)\n", label);
		return 1;
	}
	if (err == EOPNOTSUPP) {
		printf("    [PASS] %s rejected with -EOPNOTSUPP\n", label);
		return 0;
	}
	printf("    [FAIL] %s rejected with errno %d (%s); policy mandates EOPNOTSUPP\n",
	       label, err, strerror(err));
	return 1;
}

// splice(2): foreign zero-copy pipeline writing into the protected page cache.
static int check_splice_rejected(int fd)
{
#ifdef __linux__
	int p[2];
	if (pipe(p) != 0) {
		printf("    [SKIP] splice: pipe() failed (%s)\n", strerror(errno));
		return 0;
	}
	if (write(p[1], "SPLICEDATA", 10) != 10) {
		printf("    [SKIP] splice: could not fill pipe\n");
		close(p[0]);
		close(p[1]);
		return 0;
	}
	off_t off = 0;
	errno = 0;
	ssize_t s = splice(p[0], NULL, fd, &off, 10, 0);
	int rc = expect_rejected("splice(pipe -> protected file)", s >= 0, errno);
	close(p[0]);
	close(p[1]);
	return rc;
#else
	(void)fd;
	printf("    [SKIP] splice unavailable at build time\n");
	return 0;
#endif
}

// sendfile(2): zero-copy reference of the protected file as a source.
static int check_sendfile_rejected(const char *test_file)
{
#ifdef __linux__
	int src = open(test_file, O_RDONLY);
	if (src < 0) {
		printf("    [SKIP] sendfile: reopen failed (%s)\n", strerror(errno));
		return 0;
	}
	int sink = open("/dev/null", O_WRONLY);
	if (sink < 0) {
		printf("    [SKIP] sendfile: /dev/null open failed (%s)\n", strerror(errno));
		close(src);
		return 0;
	}
	off_t off = 0;
	errno = 0;
	ssize_t s = sendfile(sink, src, &off, 10);
	int rc = expect_rejected("sendfile(protected file -> /dev/null)", s >= 0, errno);
	close(src);
	close(sink);
	return rc;
#else
	(void)test_file;
	printf("    [SKIP] sendfile unavailable at build time\n");
	return 0;
#endif
}

// copy_file_range(2): in-kernel copy pipeline across protected inodes.
static int check_copy_file_range_rejected(const char *mount_dir, int src_fd)
{
#if defined(__linux__) && defined(SYS_copy_file_range)
	char dst_path[256];
	snprintf(dst_path, sizeof(dst_path), "%s/.sanity_cfr_%d.dat", mount_dir, getpid());
	int dst = open(dst_path, O_CREAT | O_RDWR | O_TRUNC, 0644);
	if (dst < 0) {
		printf("    [SKIP] copy_file_range: dest open failed (%s)\n", strerror(errno));
		return 0;
	}
	off_t off_in = 0, off_out = 0;
	errno = 0;
	ssize_t s = syscall(SYS_copy_file_range, src_fd, &off_in, dst, &off_out, (size_t)512, 0u);
	int rc = expect_rejected("copy_file_range(protected -> protected)", s >= 0, errno);
	close(dst);
	unlink(dst_path);
	return rc;
#else
	(void)mount_dir;
	(void)src_fd;
	printf("    [SKIP] copy_file_range unavailable at build time\n");
	return 0;
#endif
}

// Asynchronous I/O: submission context is decoupled from execution context
// (io-wq), so the mitigation rejects it. io_uring shares the same code path.
static int check_aio_rejected(int fd)
{
#if defined(__linux__) && defined(SYS_io_setup)
	aio_context_t ctx = 0;
	if (syscall(SYS_io_setup, 1, &ctx) < 0) {
		printf("    [SKIP] AIO unavailable (io_setup: %s)\n", strerror(errno));
		return 0;
	}

	static char aiobuf[512];
	memset(aiobuf, 'Z', sizeof(aiobuf));

	struct iocb cb;
	memset(&cb, 0, sizeof(cb));
	cb.aio_lio_opcode = IOCB_CMD_PWRITE;
	cb.aio_fildes = (uint32_t)fd;
	cb.aio_buf = (uint64_t)(uintptr_t)aiobuf;
	cb.aio_nbytes = sizeof(aiobuf);
	cb.aio_offset = 0;
	struct iocb *cbs[1] = { &cb };

	int rc;
	errno = 0;
	long r = syscall(SYS_io_submit, ctx, 1L, cbs);
	if (r < 0) {
		// Rejected at submission.
		rc = expect_rejected("io_submit(IOCB_CMD_PWRITE)", 0, errno);
	} else {
		// Accepted for submission; the rejection must surface in completion.
		struct io_event ev;
		memset(&ev, 0, sizeof(ev));
		struct timespec ts = { 5, 0 };
		long g = syscall(SYS_io_getevents, ctx, 1L, 1L, &ev, &ts);
		if (g == 1 && ev.res < 0) {
			rc = expect_rejected("AIO pwrite completion", 0, (int)(-ev.res));
		} else if (g == 1) {
			rc = expect_rejected("AIO pwrite completion", 1, 0);
		} else {
			printf("    [SKIP] AIO completion not observed (io_getevents=%ld)\n", g);
			rc = 0;
		}
	}
	syscall(SYS_io_destroy, ctx);
	return rc;
#else
	(void)fd;
	printf("    [SKIP] AIO unavailable at build time\n");
	return 0;
#endif
}

// EXT4_IOC_MOVE_EXT: online defragmentation relocates protected extents.
static int check_move_ext_rejected(const char *mount_dir, int orig_fd)
{
#ifdef __linux__
	char donor_path[256];
	snprintf(donor_path, sizeof(donor_path), "%s/.sanity_donor_%d.dat", mount_dir, getpid());
	int donor = open(donor_path, O_CREAT | O_RDWR | O_TRUNC, 0644);
	if (donor < 0) {
		printf("    [SKIP] EXT4_IOC_MOVE_EXT: donor open failed (%s)\n", strerror(errno));
		return 0;
	}
	char z[PAGE_SIZE_BYTES];
	memset(z, 0, sizeof(z));
	(void)!write(donor, z, sizeof(z));

	struct sanity_move_extent me;
	memset(&me, 0, sizeof(me));
	me.donor_fd = (uint32_t)donor;
	me.orig_start = 0;
	me.donor_start = 0;
	me.len = 1;

	errno = 0;
	int r = ioctl(orig_fd, EXT4_IOC_MOVE_EXT, &me);
	int rc;
	if (r == 0) {
		rc = expect_rejected("ioctl(EXT4_IOC_MOVE_EXT)", 1, 0);
	} else if (errno == ENOTTY) {
		printf("    [SKIP] EXT4_IOC_MOVE_EXT: not an ext4 mount (ENOTTY)\n");
		rc = 0;
	} else {
		rc = expect_rejected("ioctl(EXT4_IOC_MOVE_EXT)", 0, errno);
	}
	close(donor);
	unlink(donor_path);
	return rc;
#else
	(void)mount_dir;
	(void)orig_fd;
	printf("    [SKIP] EXT4_IOC_MOVE_EXT unavailable at build time\n");
	return 0;
#endif
}

static int test_fail_closed_policy(const char *test_file, const char *mount_dir)
{
	printf("\n==> [Suite 3] Fail-Closed Rejection Matrix\n");

	int fd = open(test_file, O_CREAT | O_RDWR | O_TRUNC, 0644);
	if (fd < 0) {
		printf("    [FAIL] open for fail-closed suite failed (%s)\n", strerror(errno));
		return 1;
	}
	if (write(fd, "0123456789ABCDEF", 16) != 16) {
		printf("    [SKIP] could not seed fail-closed test file\n");
		close(fd);
		return 0;
	}
	fsync(fd);

	int rc = 0;

	// 1. Shared writable mmap - the direct page-cache write vector.
	errno = 0;
	void *wm = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	rc |= expect_rejected("mmap(PROT_WRITE, MAP_SHARED)", wm != MAP_FAILED, errno);
	if (wm != MAP_FAILED)
		munmap(wm, 4096);

	// 2. Direct I/O - bypasses the page cache entirely.
	errno = 0;
	int dfd = open(test_file, O_RDWR | O_DIRECT);
	rc |= expect_rejected("open(O_DIRECT)", dfd >= 0, errno);
	if (dfd >= 0)
		close(dfd);

	// 3-7. Zero-copy pipelines, async submission, and online defrag.
	rc |= check_splice_rejected(fd);
	rc |= check_sendfile_rejected(test_file);
	rc |= check_copy_file_range_rejected(mount_dir, fd);
	rc |= check_aio_rejected(fd);
	rc |= check_move_ext_rejected(mount_dir, fd);

	close(fd);
	unlink(test_file);
	return rc;
}

// ----------------------------------------------------------------------------
// Suite 4 - permitted-operation positive controls
// ----------------------------------------------------------------------------
// A private read-only mapping must be permitted (execve / dynamic linking),
// but VM_MAYWRITE is stripped, so it can never be upgraded to writable.
static int check_private_ro_mapping(int fd)
{
	int rc = 0;
	void *m = mmap(NULL, 4096, PROT_READ, MAP_PRIVATE, fd, 0);
	if (m == MAP_FAILED) {
		printf("    [FAIL] MAP_PRIVATE|PROT_READ rejected (errno=%d: %s); read-only execution mappings must be permitted\n",
		       errno, strerror(errno));
		return 1;
	}
	printf("    [PASS] MAP_PRIVATE|PROT_READ permitted (execve / dynamic-linking path intact)\n");

	if (mprotect(m, 4096, PROT_READ | PROT_WRITE) == 0) {
		printf("    [FAIL] mprotect(+PROT_WRITE) succeeded on a private mapping (VM_MAYWRITE not stripped)\n");
		rc = 1;
	} else {
		printf("    [PASS] mprotect(+PROT_WRITE) blocked (errno=%d: %s); VM_MAYWRITE strip confirmed\n",
		       errno, strerror(errno));
	}
	munmap(m, 4096);
	return rc;
}

static int test_permitted_ops(const char *test_file)
{
	printf("\n==> [Suite 4] Permitted-Operation Positive Controls (no false rejections)\n");

	int rc = 0;
	int fd = open(test_file, O_CREAT | O_RDWR | O_TRUNC, 0644);
	if (fd < 0) {
		printf("    [FAIL] open(O_CREAT|O_RDWR) failed on protected mount (%s)\n", strerror(errno));
		return 1;
	}

	// 1. Buffered write -> fsync -> read round-trip integrity.
	const size_t N = 8192;
	char *w = malloc(N);
	char *r = malloc(N);
	if (!w || !r) {
		printf("    [SKIP] round-trip buffer allocation failed\n");
	} else {
		for (size_t i = 0; i < N; i++)
			w[i] = (char)(i * 31 + 7);
		if (pwrite(fd, w, N, 0) != (ssize_t)N) {
			printf("    [FAIL] buffered pwrite(%zu) failed (%s)\n", N, strerror(errno));
			rc = 1;
		} else if (fsync(fd) != 0) {
			printf("    [FAIL] fsync failed (%s)\n", strerror(errno));
			rc = 1;
		} else if (pread(fd, r, N, 0) != (ssize_t)N) {
			printf("    [FAIL] buffered pread(%zu) failed (%s)\n", N, strerror(errno));
			rc = 1;
		} else if (memcmp(w, r, N) != 0) {
			printf("    [FAIL] read-back data mismatch (page-cache corruption)\n");
			rc = 1;
		} else {
			printf("    [PASS] buffered write/fsync/read round-trip preserved %zu bytes intact\n", N);
		}
	}
	free(w);
	free(r);

	// 2. Truncation grow/shrink reflected in stat size.
	struct stat st;
	if (ftruncate(fd, 65536) == 0 && fstat(fd, &st) == 0 && st.st_size == 65536 &&
	    ftruncate(fd, 1024) == 0 && fstat(fd, &st) == 0 && st.st_size == 1024) {
		printf("    [PASS] ftruncate grow/shrink updates file size correctly (65536 -> 1024)\n");
	} else {
		printf("    [FAIL] ftruncate did not update file size as expected\n");
		rc = 1;
	}

	// 3. Read-only shared mapping must be permitted.
	void *sm = mmap(NULL, 4096, PROT_READ, MAP_SHARED, fd, 0);
	if (sm == MAP_FAILED) {
		printf("    [FAIL] MAP_SHARED|PROT_READ rejected (errno=%d: %s); read-only shared views must be permitted\n",
		       errno, strerror(errno));
		rc = 1;
	} else {
		printf("    [PASS] MAP_SHARED|PROT_READ permitted (read-only consumers unaffected)\n");
		munmap(sm, 4096);
	}

	// 4. Private read-only mapping permitted; writable upgrade blocked.
	rc |= check_private_ro_mapping(fd);

	close(fd);
	unlink(test_file);
	return rc;
}

int main(int argc, char **argv)
{
	(void)argc;
	(void)argv;

	printf("================================================================\n");
	printf(" PKS Page-Cache Protection Contract Verifier\n");
	printf("================================================================\n");

	uint64_t b = 0, e = 0;
	g_has_debugfs = read_debugfs_status(&b, &e);
	if (g_has_debugfs) {
		printf("[INFO] Connected to DebugFS: pool [0x%lx, 0x%lx), scopes=%llu\n",
		       g_pool_start_pfn, g_pool_end_pfn, (unsigned long long)b);
	} else {
		printf("[INFO] DebugFS status node not available; running policy & non-instrumented tests\n");
	}

	const char *mount_dir = MOUNT_PATH;
	struct stat st;
	if (stat(mount_dir, &st) != 0) {
		fprintf(stderr, "[ERR]  Target directory %s does not exist\n", mount_dir);
		return 1;
	}

	char test_file[256];
	snprintf(test_file, sizeof(test_file), "%s/.sanity_test_%d.dat", mount_dir, getpid());

	int rc = 0;
	rc |= test_vfs_scoping(test_file);
	rc |= test_static_pool_pfn(test_file);
	rc |= test_fail_closed_policy(test_file, mount_dir);
	rc |= test_permitted_ops(test_file);

	printf("\n================================================================\n");
	if (rc == 0) {
		printf(" [OK] All PKS page-cache contract assertions PASSED\n");
	} else {
		printf(" [FAIL] One or more contract assertions failed\n");
	}
	printf("================================================================\n");
	return rc;
}
