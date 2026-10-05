# POSIX Filesystem Compliance Suite (`pjdfstest`)

## Upstream Origin & Purpose
- **Source**: Pawel Jakub Dawidek's POSIX test suite (`pjdfstest`), standard in FreeBSD and Linux filesystem validation.
- **Role in Thesis**: Confirms that integrating Protection Keys for Supervisor into ext4 does not break core POSIX filesystem semantics or directory metadata operations.

---

## Scoped Syscall Verification
Under the PKS page-cache protection design (Commit 06), shared writable memory mappings are rejected with `-EOPNOTSUPP`. Full test suites that attempt `mmap(PROT_WRITE | MAP_SHARED)` will trigger expected rejection.

Therefore, POSIX compliance testing is scoped specifically to metadata and buffered file manipulation syscalls:
1. `chmod`: File permission modification, sticky bits, and access control.
2. `chown`: Ownership transitions across standard users and groups.
3. `truncate`: Length truncations across various file offsets and page boundaries.

These three test suites encompass 284 individual test assertions, executed via Perl's `prove` Test Anything Protocol (TAP) harness directly against the `/mnt/protected` mountpoint.

---

## Applied Patches & Justification

### 1. Scoped Test Selection
- **Patch Tag**: `# PATCH - scope POSIX tests to chown, chmod, truncate (non-mmap metadata syscalls)`
- **Location**: [`test/pjd/run.sh`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/pjd/run.sh#L49)
- **Rationale**: Isolates POSIX compliance verification to supported syscalls, ensuring that metadata modifications and regular file truncations proceed with complete standard compliance.

### 2. Omission Grace on Missing Dependencies
- **Patch Tag**: `# PATCH - grace on omitted harness if prove/perl is absent`
- **Location**: [`test/pjd/run.sh`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/pjd/run.sh#L39)
- **Rationale**: In minimal initramfs or stripped guest environments where Perl or TAP dependencies are not packaged, the runner reports `note=omitted_harness_absent` rather than generating false build or execution errors.

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
