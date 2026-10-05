# In-Kernel Invariant & Scoping Sanity Test (`sanity`)

## Overview & Purpose
- **Source**: Custom verification suite implemented in [`test/sanity/pks_sanity_test.c`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/sanity/pks_sanity_test.c).
- **Role in Thesis**: Directly tests the eight foundational invariants of the thesis implementation: thread-local write scoping across all mutation syscalls, static pool physical memory residency, and fail-closed operational filters.

---

## The Eight Invariant Verifications

[`pks_sanity_test.c`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/sanity/pks_sanity_test.c) executes eight programmatic checks against a target file on `/mnt/protected`:

| Check ID | Tested Syscall / Invariant | Verified Mechanism | Expected Outcome |
| :--- | :--- | :--- | :--- |
| **Check 1** | `write()` | Standard buffered VFS write scoping | Increments `scope_begin_count` and `scope_end_count` symmetrically |
| **Check 2** | `pwrite()` | Positional buffered write scoping | Symmetrical scoping counter increment |
| **Check 3** | `writev()` | Vector buffered write scoping | Symmetrical scoping counter increment |
| **Check 4** | `ftruncate()` | File truncation and zeroing scoping | Symmetrical scoping counter increment |
| **Check 5** | `fallocate()` | Block pre-allocation scoping | Symmetrical scoping counter increment |
| **Check 6** | Page-cache pool residency | Inspects `/proc/self/pagemap` to extract the physical PFN | PFN falls strictly within `[pool_start_pfn, pool_end_pfn]` |
| **Check 7** | Shared writable `mmap()` | Fail-closed enforcement on memory mappings | Call fails and sets `errno == EOPNOTSUPP` |
| **Check 8** | Direct I/O (`O_DIRECT`) | Fail-closed enforcement on unbuffered I/O | `open(O_DIRECT)` fails and sets `errno == EINVAL` |

---

## Kernel Telemetry Interface
The harness queries `/sys/kernel/debug/pcache_pks/status` to inspect in-kernel telemetry:
- `pool_start_pfn`: Beginning page frame number of the 256 MiB PMD-aligned direct-map pool.
- `pool_end_pfn`: Ending page frame number of the pool.
- `scope_begin_count`: Monotonic counter tracking entry into supervisor write scopes.
- `scope_end_count`: Monotonic counter tracking exit and restoration of write-disable state.

A check passes only if the operation succeeds without error, telemetry counters increment by the expected delta, and begin/end counts remain identical upon return.

---

## Operational Modality
- **`pcache_pks=on`**: The harness executes all eight checks against `/mnt/protected`. All eight checks must pass for a `PASS` verdict.
- **`pcache_pks=off`**: The PKS static pool and thread scoping hooks are intentionally dormant. The runner emits `PASS note=not_applicable_when_off`, matching the expected system state.

---

## Output Contract & Rollup
- Protected mode success:
  ```text
  STATUS node=sanity variant=on verdict=PASS passed=8
  ```
- Unmitigated baseline mode:
  ```text
  STATUS node=sanity variant=off verdict=PASS note=not_applicable_when_off
  ```
- Invariant violation:
  ```text
  STATUS node=sanity variant=on verdict=FAIL passed=<num> failed=<num>
  ```
