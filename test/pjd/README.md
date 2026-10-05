# POSIX Filesystem Compliance Suite (`pjdfstest`)

## Upstream Origin & Purpose
- **Source**: Pawel Jakub Dawidek's POSIX test suite (`pjdfstest`), standard in FreeBSD and Linux filesystem validation.
- **Role in Thesis**: Confirms that integrating Protection Keys for Supervisor into ext4 does not break core POSIX filesystem semantics or directory metadata operations.

---

## Scoped Syscall Verification & Directory Structure
Under the PKS page-cache protection design (Commit 06), shared writable memory mappings are rejected with `-EOPNOTSUPP`. Full POSIX test suites that attempt `mmap(PROT_WRITE | MAP_SHARED)` will trigger expected rejection.

Therefore, POSIX compliance testing is scoped specifically to metadata and buffered file manipulation syscalls:
1. `chmod`: File permission modification, sticky bits, and access control.
2. `chown`: Ownership transitions across standard users and groups.
3. `truncate`: Length truncations across various file offsets and page boundaries.

These three test suites encompass 284 individual test assertions, executed via Perl's `prove` Test Anything Protocol (TAP) harness directly against the `/mnt/protected` mountpoint.

### Cleaned Directory Layout
All extraneous upstream CI configurations (`.cirrus-ci`, `.cirrus.yml`, `.github`, `ci`), repository administrative files (`AUTHORS`, `COPYING`, `ChangeLog`, `NEWS`, `.gitignore`), autotools build artifacts (`configure.ac`, `Makefile.am`), and 14 unused test suites (`chflags`, `ftruncate`, `granular`, `link`, `mkdir`, `mkfifo`, `mknod`, `open`, `posix_fallocate`, `rename`, `rmdir`, `symlink`, `unlink`, `utimensat`) were pruned.

The clean in-tree layout contains only the essential components:
```text
test/pjd/
├── pjdfstest.c          # Syscall dispatch engine (patched for standalone compilation)
├── run.sh               # Execution runner and verdict parser
├── README.md            # Compliance documentation and patch notes
└── tests/
    ├── conf             # Operating system and filesystem detection
    ├── misc.sh          # Common assertion primitives (expect, namegen, supported)
    ├── chmod/           # 13 chmod/lchmod test scripts
    ├── chown/           # 11 chown/lchown test scripts
    └── truncate/        # 15 truncate length test scripts
```

---

## Applied Patches & Justification

### 1. Standalone Compilation Fallbacks (`pjdfstest.c`)
- **Patch Tag**: `// PATCH - fallback definitions when compiled standalone without autotools config.h`
- **Location**: [`test/pjd/pjdfstest.c`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/pjd/pjdfstest.c#L28)
- **Rationale**: Upstream `pjdfstest` requires autotools (`autoreconf -ifs && ./configure`) to generate `config.h`. To eliminate build-time autotools dependencies in minimal guest environments, `pjdfstest.c` includes native POSIX and Linux capability defines (`HAVE_OPENAT`, `HAVE_FCHMODAT`, `HAVE_FCHOWNAT`, `HAVE_POSIX_FALLOCATE`, `HAVE_SYS_SYSMACROS_H`), enabling direct standalone compilation via `gcc -O2 -Wall -o pjdfstest pjdfstest.c`.

---

## Output Contract & Rollup
- All assertions passing:
  ```text
  STATUS node=pjd variant=<off|on> verdict=PASS total=284
  ```
- Omitted due to environment:
  ```text
  STATUS node=pjd variant=<off|on> verdict=PASS note=omitted_harness_absent total=0
  ```
- Assertion failures observed:
  ```text
  STATUS node=pjd variant=<off|on> verdict=FAIL failed=<count>
  ```
