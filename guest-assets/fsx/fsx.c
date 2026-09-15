/*
 * fsx.c - File System Exerciser for PKS Evaluation
 *
 * Based on the classic File System Exerciser by:
 *   Copyright (C) 1991, NeXT Computer, Inc. (Avadis Tevanian, Jr.)
 *   Copyright (C) 1998-2001 Apple Computer, Inc. (Conrad Minshall, Dave Jones, Zach Brown)
 *
 * Adapted for PKS direct-map page-cache validation:
 *   - Autonomous in-memory oracle comparison (detects silent corruption down to 1 byte)
 *   - Strict bounds enforcement for static PKS pool (default 64MB max file size)
 *   - Configurable mmap write skipping (--no-mapwrite) to adhere to Commit 06 invariants
 *   - Negative testing flag (--expect-mapwrite-fail) verifying Commit 06 -EOPNOTSUPP
 *   - Reproducible PRNG seeding (-s <seed>)
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
#include <sys/mman.h>
#include <sys/stat.h>

enum op_type {
    OP_READ = 0,
    OP_WRITE,
    OP_TRUNCATE,
    OP_MAPREAD,
    OP_MAPWRITE,
    OP_TOTAL
};

static const char *op_names[] = {
    "READ", "WRITE", "TRUNCATE", "MAPREAD", "MAPWRITE"
};

/* Configuration options */
static char *target_fname = "fsx_test.bin";
static size_t max_file_size = 64 * 1024 * 1024; /* 64MB default */
static size_t max_op_size = 64 * 1024;          /* 64KB max per operation */
static unsigned long num_ops = 10000;           /* 10,000 operations */
static unsigned int seed = 0;
static bool verbose = false;
static bool allow_mapwrite = true;
static bool expect_mapwrite_fail = false;

/* State */
static int target_fd = -1;
static size_t cur_file_size = 0;
static size_t page_size = 4096;
static unsigned char *oracle_buf = NULL;
static unsigned char *io_buf = NULL;

static void print_usage(const char *prog) {
    printf("Usage: %s [options] <testfile>\n", prog);
    printf("Options:\n");
    printf("  -l <size>       Maximum file size in bytes (default: 67108864 [64MB])\n");
    printf("  -o <size>       Maximum operation size in bytes (default: 65536 [64KB])\n");
    printf("  -N <num>        Number of random operations to execute (default: 10000)\n");
    printf("  -s <seed>       PRNG random seed (default: current time)\n");
    printf("  -W              Disable MAPWRITE operations (required for PKS protected mounts)\n");
    printf("  -b              Verify that MAPWRITE fails with -EOPNOTSUPP (Commit 06 test)\n");
    printf("  -v              Verbose output for every operation\n");
    printf("  -h              Show this help message\n");
}

static void report_mismatch(size_t offset, size_t size, size_t bad_off, unsigned char exp, unsigned char act) {
    fprintf(stderr, "\n======================================================================\n");
    fprintf(stderr, " FATAL CORRUPTION DETECTED in %s!\n", target_fname);
    fprintf(stderr, " Operation range:  offset 0x%zx - 0x%zx (size: %zu)\n", offset, offset + size, size);
    fprintf(stderr, " First mismatch:   offset 0x%zx\n", bad_off);
    fprintf(stderr, " Expected byte:    0x%02x ('%c')\n", exp, (exp >= 32 && exp < 127) ? exp : '.');
    fprintf(stderr, " Actual disk byte: 0x%02x ('%c')\n", act, (act >= 32 && act < 127) ? act : '.');
    fprintf(stderr, " Replay seed:      -s %u\n", seed);
    fprintf(stderr, "======================================================================\n");
    exit(1);
}

static int do_read(void) {
    if (cur_file_size == 0)
        return 0;

    size_t offset = (size_t)(rand() % cur_file_size);
    size_t size = 1 + (size_t)(rand() % (cur_file_size - offset));
    if (size > max_op_size)
        size = max_op_size;

    if (verbose)
        printf("  OP: READ offset=0x%zx size=%zu\n", offset, size);

    if (lseek(target_fd, (off_t)offset, SEEK_SET) == (off_t)-1) {
        perror("lseek for read failed");
        exit(2);
    }

    size_t total_read = 0;
    while (total_read < size) {
        ssize_t n = read(target_fd, io_buf + total_read, size - total_read);
        if (n <= 0) {
            if (n < 0 && errno == EINTR)
                continue;
            fprintf(stderr, "read error: unexpected EOF or error at offset 0x%zx: %s\n",
                    offset + total_read, strerror(errno));
            exit(2);
        }
        total_read += (size_t)n;
    }

    /* Compare against oracle buffer */
    for (size_t i = 0; i < size; i++) {
        if (io_buf[i] != oracle_buf[offset + i]) {
            report_mismatch(offset, size, offset + i, oracle_buf[offset + i], io_buf[i]);
        }
    }

    return 1;
}

static int do_write(void) {
    if (cur_file_size >= max_file_size)
        return 0;

    size_t offset = (size_t)(rand() % max_file_size);
    size_t size = 1 + (size_t)(rand() % max_op_size);
    if (offset + size > max_file_size)
        size = max_file_size - offset;

    /* Fill random data */
    unsigned char pattern = (unsigned char)(rand() % 256);
    for (size_t i = 0; i < size; i++) {
        io_buf[i] = (unsigned char)(pattern + (i & 0xFF));
    }

    if (verbose)
        printf("  OP: WRITE offset=0x%zx size=%zu\n", offset, size);

    /* If writing past current EOF, zero out the hole */
    if (offset > cur_file_size) {
        memset(oracle_buf + cur_file_size, 0, offset - cur_file_size);
    }

    /* Update oracle buffer */
    memcpy(oracle_buf + offset, io_buf, size);
    if (offset + size > cur_file_size)
        cur_file_size = offset + size;

    if (lseek(target_fd, (off_t)offset, SEEK_SET) == (off_t)-1) {
        perror("lseek for write failed");
        exit(2);
    }

    size_t total_written = 0;
    while (total_written < size) {
        ssize_t n = write(target_fd, io_buf + total_written, size - total_written);
        if (n <= 0) {
            if (n < 0 && errno == EINTR)
                continue;
            fprintf(stderr, "write error at offset 0x%zx: %s\n",
                    offset + total_written, strerror(errno));
            exit(2);
        }
        total_written += (size_t)n;
    }

    return 1;
}

static int do_truncate(void) {
    size_t new_size = (size_t)(rand() % max_file_size);

    if (verbose)
        printf("  OP: TRUNCATE old=0x%zx new=0x%zx\n", cur_file_size, new_size);

    if (ftruncate(target_fd, (off_t)new_size) != 0) {
        perror("ftruncate failed");
        exit(2);
    }

    if (new_size > cur_file_size) {
        /* POSIX requires up-truncate to zero-fill extension */
        memset(oracle_buf + cur_file_size, 0, new_size - cur_file_size);
    } else if (new_size < cur_file_size) {
        /* Zero out truncated region in oracle so future extensions see zeros */
        memset(oracle_buf + new_size, 0, cur_file_size - new_size);
    }
    cur_file_size = new_size;

    return 1;
}

static int do_mapread(void) {
    if (cur_file_size == 0)
        return 0;

    size_t offset = (size_t)(rand() % cur_file_size);
    size_t size = 1 + (size_t)(rand() % (cur_file_size - offset));
    if (size > max_op_size)
        size = max_op_size;

    /* Align offset down to page boundary for mmap */
    size_t page_offset = offset % page_size;
    size_t map_offset = offset - page_offset;
    size_t map_length = size + page_offset;

    if (verbose)
        printf("  OP: MAPREAD offset=0x%zx size=%zu\n", offset, size);

    void *addr = mmap(NULL, map_length, PROT_READ, MAP_SHARED, target_fd, (off_t)map_offset);
    if (addr == MAP_FAILED) {
        perror("mmap MAPREAD failed");
        exit(2);
    }

    unsigned char *ptr = (unsigned char *)addr + page_offset;
    for (size_t i = 0; i < size; i++) {
        if (ptr[i] != oracle_buf[offset + i]) {
            munmap(addr, map_length);
            report_mismatch(offset, size, offset + i, oracle_buf[offset + i], ptr[i]);
        }
    }

    if (munmap(addr, map_length) != 0) {
        perror("munmap failed");
        exit(2);
    }

    return 1;
}

static int do_mapwrite(void) {
    if (expect_mapwrite_fail) {
        /* Negative test: verify Commit 06 reject policy */
        void *addr = mmap(NULL, page_size, PROT_READ | PROT_WRITE, MAP_SHARED, target_fd, 0);
        if (addr != MAP_FAILED) {
            munmap(addr, page_size);
            fprintf(stderr, "[ERR] Commit 06 violation: MAP_SHARED writable mmap succeeded on protected file!\n");
            exit(3);
        }
        if (errno == EOPNOTSUPP || errno == EINVAL || errno == EACCES) {
            if (verbose)
                printf("  [OK] Expected Commit 06 rejection verified (errno=%d: %s)\n", errno, strerror(errno));
            return 1;
        }
        fprintf(stderr, "Unexpected errno for MAP_SHARED mmap: %d (%s)\n", errno, strerror(errno));
        exit(3);
    }

    if (!allow_mapwrite)
        return 0;

    if (cur_file_size >= max_file_size)
        return 0;

    size_t offset = (size_t)(rand() % max_file_size);
    size_t size = 1 + (size_t)(rand() % max_op_size);
    if (offset + size > max_file_size)
        size = max_file_size - offset;

    /* If writing past EOF, extend file first so mmap space exists */
    if (offset + size > cur_file_size) {
        if (ftruncate(target_fd, (off_t)(offset + size)) != 0) {
            perror("ftruncate before mapwrite failed");
            exit(2);
        }
        memset(oracle_buf + cur_file_size, 0, (offset + size) - cur_file_size);
        cur_file_size = offset + size;
    }

    size_t page_offset = offset % page_size;
    size_t map_offset = offset - page_offset;
    size_t map_length = size + page_offset;

    if (verbose)
        printf("  OP: MAPWRITE offset=0x%zx size=%zu\n", offset, size);

    void *addr = mmap(NULL, map_length, PROT_READ | PROT_WRITE, MAP_SHARED, target_fd, (off_t)map_offset);
    if (addr == MAP_FAILED) {
        perror("mmap MAPWRITE failed");
        exit(2);
    }

    unsigned char *ptr = (unsigned char *)addr + page_offset;
    unsigned char pattern = (unsigned char)(rand() % 256);
    for (size_t i = 0; i < size; i++) {
        unsigned char val = (unsigned char)(pattern + (i & 0xFF));
        ptr[i] = val;
        oracle_buf[offset + i] = val;
    }

    if (msync(addr, map_length, MS_SYNC) != 0) {
        perror("msync failed");
        exit(2);
    }

    if (munmap(addr, map_length) != 0) {
        perror("munmap failed");
        exit(2);
    }

    return 1;
}

int main(int argc, char **argv) {
    int opt;
    while ((opt = getopt(argc, argv, "l:o:N:s:Wbvh")) != -1) {
        switch (opt) {
            case 'l':
                max_file_size = (size_t)strtoull(optarg, NULL, 0);
                break;
            case 'o':
                max_op_size = (size_t)strtoull(optarg, NULL, 0);
                break;
            case 'N':
                num_ops = strtoul(optarg, NULL, 0);
                break;
            case 's':
                seed = (unsigned int)strtoul(optarg, NULL, 0);
                break;
            case 'W':
                allow_mapwrite = false;
                break;
            case 'b':
                expect_mapwrite_fail = true;
                break;
            case 'v':
                verbose = true;
                break;
            case 'h':
            default:
                print_usage(argv[0]);
                return (opt == 'h') ? 0 : 1;
        }
    }

    if (optind < argc) {
        target_fname = argv[optind];
    }

    if (seed == 0) {
        seed = (unsigned int)time(NULL);
    }
    srand(seed);

    page_size = (size_t)sysconf(_SC_PAGESIZE);

    printf("======================================================================\n");
    printf(" File System Exerciser (fsx) - PKS Integrity Validation\n");
    printf("   Target file:       %s\n", target_fname);
    printf("   Max file size:     %zu bytes (%.2f MB)\n", max_file_size, (double)max_file_size / (1024 * 1024));
    printf("   Max op size:       %zu bytes\n", max_op_size);
    printf("   Operations:        %lu\n", num_ops);
    printf("   Random seed:       %u\n", seed);
    printf("   MAPWRITE enabled:  %s\n", allow_mapwrite ? "YES" : "NO (PKS mode)");
    printf("   Negative testing:  %s\n", expect_mapwrite_fail ? "YES (verifying -EOPNOTSUPP)" : "NO");
    printf("======================================================================\n");

    oracle_buf = (unsigned char *)malloc(max_file_size);
    io_buf = (unsigned char *)malloc(max_file_size > max_op_size ? max_file_size : max_op_size);
    if (!oracle_buf || !io_buf) {
        fprintf(stderr, "Out of memory allocating buffers\n");
        return 1;
    }
    memset(oracle_buf, 0, max_file_size);

    target_fd = open(target_fname, O_RDWR | O_CREAT | O_TRUNC, 0666);
    if (target_fd < 0) {
        perror("open failed");
        return 1;
    }

    unsigned long completed = 0;
    unsigned long counts[OP_TOTAL] = {0};

    for (unsigned long i = 0; i < num_ops; i++) {
        int op = rand() % OP_TOTAL;
        int executed = 0;

        switch (op) {
            case OP_READ:
                executed = do_read();
                break;
            case OP_WRITE:
                executed = do_write();
                break;
            case OP_TRUNCATE:
                executed = do_truncate();
                break;
            case OP_MAPREAD:
                executed = do_mapread();
                break;
            case OP_MAPWRITE:
                executed = do_mapwrite();
                break;
        }

        if (executed) {
            completed++;
            counts[op]++;
        }

        if (!verbose && (completed % 2500 == 0 || completed == num_ops)) {
            printf("  Progress: %lu / %lu operations completed...\n", completed, num_ops);
        }
    }

    /* Final integrity check: full scan of whole file against oracle */
    printf("==> Performing final whole-file integrity verification...\n");
    if (lseek(target_fd, 0, SEEK_SET) == (off_t)-1) {
        perror("final lseek failed");
        return 1;
    }

    size_t total_verified = 0;
    while (total_verified < cur_file_size) {
        size_t chunk = cur_file_size - total_verified;
        if (chunk > max_op_size)
            chunk = max_op_size;

        ssize_t n = read(target_fd, io_buf, chunk);
        if (n <= 0) {
            fprintf(stderr, "read error during final verification at offset %zu\n", total_verified);
            return 1;
        }
        for (ssize_t j = 0; j < n; j++) {
            if (io_buf[j] != oracle_buf[total_verified + (size_t)j]) {
                report_mismatch(0, cur_file_size, total_verified + (size_t)j,
                                oracle_buf[total_verified + (size_t)j], io_buf[j]);
            }
        }
        total_verified += (size_t)n;
    }

    close(target_fd);
    unlink(target_fname);
    free(oracle_buf);
    free(io_buf);

    printf("\n======================================================================\n");
    printf(" [OK] SUCCESS! All %lu operations verified with zero mismatches.\n", completed);
    printf(" Operation breakdown:\n");
    for (int i = 0; i < OP_TOTAL; i++) {
        printf("   %-12s: %lu\n", op_names[i], counts[i]);
    }
    printf("======================================================================\n");

    return 0;
}
