# Security Exploit Evaluation Axis (`sec/`)

## Executive Summary
The security axis evaluates end-to-end exploit neutralization of dirty page-cache write vulnerabilities using Protection Keys for Supervisor (PKS) hardware write isolation.

Under the unmitigated Linux kernel, memory corruption flaws in asynchronous kernel subsystems allow unprivileged attackers to splice or write arbitrary data into clean, file-backed page-cache pages without standard discretionary access control (DAC) checks. The security axis empirically verifies that:
1. Under `pcache_pks=off`, exploits successfully overwrite target victim pages on disk ([`marker=altered`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec/dirty-frag/README.md)), confirming real vulnerability.
2. Under `pcache_pks=on`, hardware write protection prevents unauthorized stores to protected direct-map pages, either trapping the violation as an unhandled fault ([`fail_closed_panic`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec/copy-fail/README.md)) or blocking the store so the victim data remains pristine ([`marker=intact`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec/fragnesia/README.md)).

---

## Evaluated Vulnerabilities & PoC Suites

```text
sec/
├── copy-fail/    # CVE-2022-2639: AF_ALG splice write out-of-bounds corruption
├── dirty-frag/   # CVE-2022-43284: XFRM / ESP in UDP socket buffer splice corruption
├── fragnesia/    # CVE-2026-46300: XFRM ESP-in-TCP page-cache replacement
├── run.sh        # Host aggregator script with 3-tier console reporting
└── result.csv    # Sole persistent structured record for the security axis
```

Detailed reviewer guides for each exploit:
- [`sec/copy-fail/README.md`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec/copy-fail/README.md)
- [`sec/dirty-frag/README.md`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec/dirty-frag/README.md)
- [`sec/fragnesia/README.md`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec/fragnesia/README.md)

---

## Execution Model: Isolated Virtual Machine Invocations

Unlike the compliance (`test/`) and performance (`perf/`) axes, where non-destructive workloads run in a single consolidated VM boot, the security axis executes **each exploit leaf in an independent virtual machine instance** for each mode (`off`, `on`).

### Rationale
1. **Fail-Closed Kernel Panics**: Softirq and workqueue exploits trigger unhandled supervisor page faults when PKS write-disable is active, deliberately halting the kernel to prevent memory corruption. A fresh virtual machine boot is mandatory for subsequent tests.
2. **Victim State Cleanliness**: Each run mounts a fresh ext4 filesystem with a newly initialized victim file containing a unique sentinel marker, preventing cross-test pollution.

---

## Target Preparation & Marker Verification Protocol

Each exploit leaf follows an identical five-step lifecycle:
1. **Target Preparation**: Writes a known sentinel marker (e.g. `PKS_CLEAN_MARKER_...`) into `/mnt/protected/victim_file`.
2. **Page-Cache Synchronization**: Invokes `sync` and flushes the page cache via `echo 3 > /proc/sys/vm/drop_caches` to force the kernel to re-read from physical storage upon next access.
3. **PoC Execution**: Executes the unprivileged PoC under `testuser` credentials. Interactive shells (`execlp("/bin/bash")`, `su`) are patched out to support headless automated benchmarking.
4. **Memory & Disk Inspection**: Inspects the first 256 bytes of `/mnt/protected/victim_file`. If the clean marker persists, the outcome is recorded as `marker=intact`; if overwritten, `marker=altered`.
5. **Crash & Panic Harvesting**: The host aggregator parses the serial transcript. If a kernel panic occurs matching `PKS_PANIC_REGEX` while PKS is active, the outcome is recorded as `fail_closed_panic`.

---

## Output Architecture & Channel Separation

```
                             +-----------------------------------+
                             |             make sec              |
                             +-----------------+-----------------+
                                               |
                     +-------------------------+-------------------------+
                     |                                                   |
          Console Terminal Stream                             Persistent Data Stream
          (stdout via sec/run.sh)                                (strictly on disk)
                     |                                                   |
     +---------------+---------------+                   +---------------+---------------+
     |               |               |                   |                               |
  Header          Live Log        Footer            Transcripts                     Dataset
 88-col banner  per-mode/leaf  Summary Table     sec/*/raw-{off,on}.log          sec/result.csv
from sec/run.sh from sec/run.sh from sec/run.sh   (serial output)             (sole structured log)
```

1. **Terminal Console**: Driven entirely by [`sec/run.sh`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec/run.sh). An 88-column header opens the run, followed by per-leaf live execution logs. The summary footer displays side-by-side comparison tables between `off` and `on` modes.
2. **Persistent Storage**: All structured test records are stored strictly in [`sec/result.csv`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec/result.csv). No intermediate or leaf `result.log` files are created.
3. **Raw Transcripts**: Complete guest serial transcripts are preserved in `sec/<leaf>/raw-off.log` and `sec/<leaf>/raw-on.log` for post-run fault analysis.

---

## Result CSV Schema

The single output log [`sec/result.csv`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec/result.csv) follows this structure:

```csv
node,variant,verdict,outcome
copy-fail,off,PASS,altered
copy-fail,on,PASS,fail_closed_panic
dirty-frag,off,FAIL,intact
dirty-frag,on,PASS,intact
fragnesia,off,FAIL,intact
fragnesia,on,PASS,intact
sec,all,FAIL,passed=4_failed=2
```
