# File System Exerciser (`fsx`) Stress & Integrity Test

## Upstream Origin & Purpose
- **Source**: Classic File System Exerciser (`fsx.c`), ported from the Linux Test Project (LTP) and Apple Darwin sources.
- **Role in Thesis**: Validates page-cache data integrity and functional correctness under continuous random mutation. It ensures that thread-local PKS write scoping does not induce silent data corruption during concurrent reads, writes, truncations, and read-only memory mappings.

### Directory Layout
The suite contains only the essential components:
```text
test/fsx/
├── fsx.c        # Oracle file system exerciser (patched for PKS bounds and mmap policy)
├── fsx          # Precompiled guest testing binary
├── run.sh       # Execution runner and verdict parser
└── README.md    # Architecture documentation and patch notes
```

---

## Test Mechanics & Oracle Validation
`fsx` allocates a shadow memory buffer in user space that tracks the exact expected state of the test file. Over 10,000 randomized operations, `fsx` executes:
1. `READ`: Reads arbitrary file offsets and validates byte contents against the in-memory shadow oracle.
2. `WRITE`: Writes random byte sequences to the file and mirrors the mutation into the shadow oracle.
3. `TRUNCATE`: Shrinks or extends the file via `ftruncate`, zero-filling extended ranges in both disk and oracle buffers.
4. `MAPREAD`: Creates a shared read-only memory mapping via `mmap(PROT_READ, MAP_SHARED)` and verifies mapped pages against the oracle.
5. `MAPWRITE`: Shared writable mappings, handled according to PKS mitigation state.

If any byte retrieved from disk fails to match the oracle, `fsx` immediately aborts with non-zero exit status and logs the precise byte offset, expected value, and observed corruption. Exit code 0 is authoritative proof of 0 errors across 10,000 operations.

---

## Applied Patches & Justification

The following modifications are tagged in [`fsx.c`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/fsx/fsx.c):

### 1. Pool Bounds Enforcement
- **Patch Tag**: `// PATCH - pool bounds: default 64MB max file size to prevent pool exhaustion`
- **Location**: [`test/fsx/fsx.c`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/fsx/fsx.c#L46)
- **Rationale**: The PKS isolated direct-map page-cache pool has a static size of 256 MiB. Capping the maximum file size to 64 MiB prevents memory exhaustion during randomized file expansions while leaving ample space for kernel metadata and concurrent cache pages.

### 2. MAPWRITE Bypass on PKS Mounts
- **Patch Tag**: `// PATCH - disable MAPWRITE on PKS protected mount (-W)`
- **Location**: [`test/fsx/fsx.c`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/fsx/fsx.c#L52), [`test/fsx/fsx.c`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/fsx/fsx.c#L313)
- **Rationale**: Under Commit 06 of the PKS kernel implementation, shared writable memory mappings (`mmap(PROT_WRITE | MAP_SHARED)`) on the protected ext4 filesystem are intentionally rejected by kernel policy with `-EOPNOTSUPP`. This fail-closed design invariant prevents user-space write access from bypassing supervisor domain write gates. Passing `-W` disables `MAPWRITE` under `pcache_pks=on`, preventing expected rejection from being treated as a test failure.

### 3. Negative Assertion of Policy Rejection
- **Patch Tag**: `// PATCH - verify MAPWRITE fails with -EOPNOTSUPP (-b)`
- **Location**: [`test/fsx/fsx.c`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/fsx/fsx.c#L55), [`test/fsx/fsx.c`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/fsx/fsx.c#L318), [`test/fsx/fsx.c`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/fsx/fsx.c#L368)
- **Rationale**: Provides an active verification flag ensuring that attempting `mmap(PROT_WRITE | MAP_SHARED)` on the protected partition reliably returns `-EOPNOTSUPP`, verifying the security enforcement boundary.

### 4. CLI Option Handling for PKS Testing
- **Patch Tag**: `// PATCH - CLI options for PKS compliance and negative testing`
- **Location**: [`test/fsx/fsx.c`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/fsx/fsx.c#L71)
- **Rationale**: Exposes `-W` and `-b` flags in the usage description and argument parsing logic.

---

## Output Contract & Rollup
- Output STATUS line:
  ```text
  STATUS node=fsx variant=<off|on> verdict=PASS ops=10000 errors=0
  ```
- Failure indicator:
  ```text
  STATUS node=fsx variant=<off|on> verdict=FAIL rc=<exit_code>
  ```
