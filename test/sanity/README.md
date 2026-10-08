# PKS Page-Cache Protection Contract Verifier (`sanity`)

## Overview & Purpose
- **Source**: [`test/sanity/pks_sanity_test.c`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/sanity/pks_sanity_test.c) — a purpose-built user-space verifier for this thesis.
- **Role in thesis**: This is the **primary compliance evidence** for the mitigation. Every assertion maps directly onto a documented invariant of the PKS page-cache design (`context/overview.md`), rather than exercising generic POSIX semantics that the mechanism does not touch. The protection domain is **file-data folios of regular files on a protected mount**; inode metadata, directory entries, and the JBD2 journal deliberately remain in normal memory, so the verifier concentrates on the data path, the static pool, and the fail-closed boundary — exactly where the mechanism lives.

Why a bespoke verifier instead of a stock filesystem suite: a conformance suite measures POSIX *metadata* behaviour that operates outside the protected pool, producing a large volume of passing assertions with little bearing on the mitigation. This verifier instead proves the three properties the thesis actually claims — **sanctioned writes are scoped**, **protected folios live in the pool**, and **every unsanctioned write path is refused** — and then confirms the mechanism does **not** over-block legitimate I/O.

---

## The Four Suites

[`pks_sanity_test.c`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/sanity/pks_sanity_test.c) runs against a scratch file on `/mnt/protected` and emits one `[PASS]`/`[FAIL]` line per assertion. Assertions whose preconditions are unmet (no DebugFS, non-root, unsupported syscall at build time) emit `[SKIP]` and are not counted.

### Suite 1 — Sanctioned write-path scoping
Confirms that each mutation syscall opens and closes a thread-local write scope, that reads do not, and that the global scope counters stay balanced (leak-free). Requires the `CONFIG_PCACHE_PKS_DEBUG` DebugFS counters; otherwise skipped.

| Check | Syscall / invariant | Expected telemetry |
| :--- | :--- | :--- |
| 1 | `write()` | `scope_begin_count` and `scope_end_count` both +1, equal |
| 2 | `pwrite()` | symmetric scope increment |
| 3 | `writev()` | symmetric scope increment |
| 4 | `ftruncate()` | symmetric scope increment (partial-block zeroing) |
| 5 | `fallocate()` | symmetric scope increment (zero-range / preallocation) |
| 6 | `pread()` | **zero** write-scope toggles (read-path parity) |
| 7 | balance | total begin count == total end count |

### Suite 2 — Static-pool page-cache residency
Writes a 4 MiB file, maps it read-only, forces page-cache residency, and walks `/proc/self/pagemap` to resolve each resident page's physical PFN. **Every** resident folio must fall within `[pool_start_pfn, pool_end_pfn)`. Requires root (for `pagemap` PFNs) and the DebugFS pool bounds; otherwise skipped.

### Suite 3 — Fail-closed rejection matrix
Confirms that every uncoordinated or foreign write path is refused with `-EOPNOTSUPP`. A rejection with any other errno, or an operation that is **permitted**, is a failure.

| Check | Operation | Threat it closes |
| :--- | :--- | :--- |
| 1 | `mmap(PROT_WRITE, MAP_SHARED)` | direct user-space writes into protected folios |
| 2 | `open(O_DIRECT)` | page-cache-bypassing unbuffered I/O |
| 3 | `splice(pipe -> file)` | zero-copy pipeline writing the page cache |
| 4 | `sendfile(file -> sink)` | zero-copy reference of a protected source |
| 5 | `copy_file_range()` | in-kernel copy pipeline across protected inodes |
| 6 | AIO `io_submit(PWRITE)` | async submission decoupled from execution context (shared with `io_uring`/io-wq) |
| 7 | `ioctl(EXT4_IOC_MOVE_EXT)` | online defragmentation relocating protected extents |

AIO represents the asynchronous class; `io_uring` is rejected by the same code path and is not re-tested to keep the harness dependency-free. Kernel-internal `__kernel_write()` rejection is not reachable from user space and is covered by the in-kernel path, not here.

### Suite 4 — Permitted-operation positive controls
Proves the mechanism does **not** over-block legitimate use — the "no false rejections" guarantee that a compliance axis must establish.

| Check | Operation | Expected |
| :--- | :--- | :--- |
| 1 | buffered `pwrite` → `fsync` → `pread` of 8 KiB | byte-for-byte round-trip (no corruption) |
| 2 | `ftruncate` grow then shrink | `st_size` tracks 65536 → 1024 |
| 3 | `mmap(PROT_READ, MAP_SHARED)` | permitted (read-only consumers unaffected) |
| 4 | `mmap(PROT_READ, MAP_PRIVATE)` | permitted (`execve` / dynamic-linking path) |
| 4b | `mprotect(+PROT_WRITE)` on that private map | **blocked** — `VM_MAYWRITE` was stripped |

---

## Kernel Telemetry Interface
Suites 1–2 query `/sys/kernel/debug/pcache_pks/status`:
- `pool_start_pfn` / `pool_end_pfn`: bounds of the 256 MiB PMD-aligned direct-map pool.
- `scope_begin_count` / `scope_end_count`: monotonic counters for entry into and exit from supervisor write scopes (a `scope_count:` line is also accepted as a combined value).

When the DebugFS node is absent (kernel built without `CONFIG_PCACHE_PKS_DEBUG`), Suites 1–2 skip and the verdict rests on the policy and positive-control suites, which need no telemetry.

---

## Operational Modality
- **`pcache_pks=on`**: the verifier runs all four suites against `/mnt/protected`. Any `[FAIL]` fails the leaf.
- **`pcache_pks=off`**: the pool and scoping hooks are dormant, so the runner does not execute the binary and emits `PASS note=not_applicable_when_off`.

---

## Output Contract & Rollup
The runner ([`test/sanity/run.sh`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/sanity/run.sh)) derives the verdict by counting `[PASS]`/`[FAIL]` lines:

- Protected mode, all assertions satisfied:
  ```text
  STATUS node=sanity variant=on verdict=PASS passed=<num>
  ```
- Unmitigated baseline mode:
  ```text
  STATUS node=sanity variant=off verdict=PASS note=not_applicable_when_off
  ```
- Contract violation:
  ```text
  STATUS node=sanity variant=on verdict=FAIL passed=<num> failed=<num>
  ```

The exact `passed=` count varies with the environment, because `[SKIP]` assertions (no DebugFS, non-root, or a syscall unavailable at build time) drop out of the tally; a `FAIL` is emitted only for a genuine contract violation.
