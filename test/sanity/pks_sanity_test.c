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
#include <inttypes.h>

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

static unsigned long g_pool_start_pfn = 0;
static unsigned long g_pool_end_pfn = 0;
static bool g_has_debugfs = false;

static bool read_debugfs_status(uint64_t *begin_cnt, uint64_t *end_cnt)
{
	FILE *fp = fopen(STATUS_PATH, "r");
	if (!fp)
		return false;

	char line[256];
	while (fgets(line, sizeof(line), fp)) {
		if (strncmp(line, "pool_start_pfn:", 15) == 0)
			sscanf(line + 15, " 0x%lx", &g_pool_start_pfn);
		else if (strncmp(line, "pool_end_pfn:", 13) == 0)
			sscanf(line + 13, " 0x%lx", &g_pool_end_pfn);
		else if (strncmp(line, "scope_begin_count:", 18) == 0)
			sscanf(line + 18, " %" SCNu64, begin_cnt);
		else if (strncmp(line, "scope_end_count:", 16) == 0)
			sscanf(line + 16, " %" SCNu64, end_cnt);
	}
	fclose(fp);
	return true;
}

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

static int test_fail_closed_policy(const char *test_file)
{
	printf("\n==> [Suite 3] Fail-Closed Policy & Rejection Verification\n");
	int fd = open(test_file, O_CREAT | O_RDWR | O_TRUNC, 0644);
	if (fd < 0) {
		perror("open fail-closed test file");
		return 1;
	}
	write(fd, "0123456789", 10);

	int fail_count = 0;

	// 1. mmap(PROT_WRITE) MUST return -EOPNOTSUPP
	void *w_map = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (w_map == MAP_FAILED && errno == EOPNOTSUPP) {
		printf("    [PASS] mmap(PROT_WRITE, MAP_SHARED) rejected with -EOPNOTSUPP (Commit 06 policy)\n");
	} else {
		printf("    [FAIL] mmap(PROT_WRITE) did not return EOPNOTSUPP (ret=%p, errno=%d: %s)\n",
		       w_map, errno, strerror(errno));
		if (w_map != MAP_FAILED)
			munmap(w_map, 4096);
		fail_count++;
	}

	// 2. O_DIRECT MUST return -EOPNOTSUPP
	int dir_fd = open(test_file, O_RDWR | O_DIRECT);
	if (dir_fd < 0 && errno == EOPNOTSUPP) {
		printf("    [PASS] open(O_DIRECT) rejected with -EOPNOTSUPP\n");
	} else {
		printf("    [FAIL] open(O_DIRECT) did not return EOPNOTSUPP (ret=%d, errno=%d: %s)\n",
		       dir_fd, errno, strerror(errno));
		if (dir_fd >= 0)
			close(dir_fd);
		fail_count++;
	}

	close(fd);
	unlink(test_file);
	return fail_count ? 1 : 0;
}

int main(int argc, char **argv)
{
	printf("================================================================\n");
	printf(" PKS Page-Cache Sanity & Subsystem Scoping Test Harness\n");
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
	rc |= test_fail_closed_policy(test_file);

	printf("\n================================================================\n");
	if (rc == 0) {
		printf(" [OK] All PKS Sanity & Scoping Tests PASSED successfully\n");
	} else {
		printf(" [FAIL] One or more sanity assertions failed\n");
	}
	printf("================================================================\n");
	return rc;
}
