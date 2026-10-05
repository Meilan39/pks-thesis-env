# Compliance & Integrity Evaluation Axis (`test/`)

## Executive Summary
The compliance axis evaluates the functional correctness, POSIX compatibility, and hardware architectural integrity of the Protection Keys for Supervisor (PKS) direct-map page-cache mitigation.

Enforcing hardware write isolation on the kernel page cache modifies critical paths across the virtual filesystem (VFS) and memory management subsystems. The compliance axis proves that:
1. Thread-local write scoping does not cause silent data corruption or regression during randomized stress operations ([`fsx`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/fsx/README.md)).
2. Low-level CPU key allocation, register context switching, and supervisor trap recovery operate according to Intel architectural specifications ([`pks-unit`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/pks-unit/README.md)).
3. Core POSIX filesystem operations, access control, and directory semantics remain intact on protected ext4 mounts ([`pjd`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/pjd/README.md)).
4. All in-kernel write scopes, static pool physical residency bounds, and fail-closed filters are actively enforced ([`sanity`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/sanity/README.md)).

---

## Suite Structure & Documentation Map

```text
test/
├── fsx/          # File System Exerciser (10,000 ops oracle comparison)
├── pks-unit/     # Intel upstream x86 PKS architectural selftest
├── pjd/          # POSIX filesystem compliance (pjdfstest TAP harness)
└── sanity/       # 8 custom in-kernel invariant and scoping checks
```

- Detailed reviewer guides for each suite:
  - [`test/fsx/README.md`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/fsx/README.md)
  - [`test/pks-unit/README.md`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/pks-unit/README.md)
  - [`test/pjd/README.md`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/pjd/README.md)
  - [`test/sanity/README.md`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/sanity/README.md)

---

## Execution Model: Consolidated Boot

Unlike the security axis ([`sec/`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec)), where individual exploits intentionally trigger kernel panics or supervisor faults and require separate virtual machine invocations, compliance workloads are non-destructive.

All four compliance leaves execute in sequence within a single virtual machine boot per mode (`off`, `on`):
1. **Mode `off` (Baseline)**: Evaluates unmitigated kernel behavior on standard ext4 mounts.
2. **Mode `on` (Hardware PKS)**: Evaluates behavior when `pcache_pks=on` is passed on the kernel command line and `-o pks_pagecache` is mounted on `/mnt/protected`.

This consolidated boot structure reduces overall evaluation time while guaranteeing identical system state across all tests.

---

## Output Architecture & Channel Separation

```
                             +-----------------------------------+
                             |             make test             |
                             +-----------------+-----------------+
                                               |
                     +-------------------------+-------------------------+
                     |                                                   |
          Console Terminal Stream                             Persistent Data Stream
          (stdout via test/run.sh)                               (strictly on disk)
                     |                                                   |
     +---------------+---------------+                   +---------------+---------------+
     |               |               |                   |                               |
  Header          Live Log        Footer            Transcripts                     Dataset
 88-col banner  per-mode/leaf  Summary Table     test/raw-{off,on}.log           test/result.csv
from test/run.sh from test/run.sh from test/run.sh   (serial output)             (sole structured log)
```

1. **Terminal Console**: Driven entirely by [`test/run.sh`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/run.sh). Background QEMU notices are silenced (`>/dev/null`), presenting an 88-column header, a live execution stream for each mode and leaf, and a summary table comparing `off` versus `on` modes side by side.
2. **Persistent Storage**: All structured test records are written strictly to [`test/result.csv`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/result.csv). No intermediate or per-leaf `result.log` files are created.
3. **Raw Transcripts**: Serial console logs from the guest virtual machine are saved to [`test/raw-off.log`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/raw-off.log) and [`test/raw-on.log`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/raw-on.log) for auditing.

---

## Result CSV Schema

The single output log [`test/result.csv`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/test/result.csv) follows this structure:

```csv
node,variant,verdict,details
fsx,off,PASS,ops=10000 errors=0
pjd,off,PASS,total=284
pks-unit,off,PASS,ok
sanity,off,PASS,not_applicable_when_off
fsx,on,PASS,ops=10000 errors=0
pjd,on,PASS,total=284
pks-unit,on,PASS,ok
sanity,on,PASS,passed=8
test,all,PASS,passed=8_failed=0
```
