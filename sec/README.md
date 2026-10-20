# Security Exploit Evaluation Axis (`sec/`)

## Executive Summary
The security axis evaluates end-to-end exploit neutralization of dirty page-cache write vulnerabilities using Protection Keys for Supervisor (PKS) hardware write isolation.

Under the unmitigated Linux kernel, memory corruption flaws in asynchronous kernel subsystems allow unprivileged attackers to splice or write arbitrary data into clean, file-backed page-cache pages without standard discretionary access control (DAC) checks. The security axis empirically verifies that:
1. Under `pcache_pks=off`, exploits successfully overwrite target victim pages on disk ([`marker=altered`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec/dirty-frag/README.md)), confirming real vulnerability.
2. Under `pcache_pks=on`, hardware write protection prevents unauthorized stores to protected direct-map pages, neutralizing the unauthorized writes in place so the victim data remains pristine ([`marker=intact`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec/copy-fail/README.md)) without crashing the kernel. Any kernel panic or oops is strictly evaluated as `FAIL`.

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

## Execution Model: One Boot Per Mode, All Leaves Batched

The security axis boots the substrate **once per mode** (`off`, then `on`) and runs
all three exploit leaves in that single boot — the same consolidated model as the
compliance (`test/`) and performance (`perf/`) axes. This supersedes the former
one-isolated-VM-per-leaf model (six boots), which existed only because a fail-closed
kernel panic would halt the VM.

### Rationale
1. **The stateless fault handler no longer panics.** Every vector is neutralized in
   place (syscall context: the task is killed; softirq/workqueue context: each stray
   store is suppressed by advancing past it). The kernel survives all three exploits
   in one boot, so per-leaf isolation is unnecessary — and on bare metal this collapses
   six reboots into two.
2. **Victim-state cleanliness is preserved sequentially.** The dispatcher runs the
   leaves in order; each re-seeds `/mnt/protected/victim_file` with its own unique
   sentinel marker immediately before running, so sharing the file across leaves in one
   boot cannot cross-pollute.
3. **Per-leaf harvest from a shared transcript.** The dispatcher emits a
   `### PKS-LEAF <leaf>` delimiter before each leaf; `sec/run.sh` isolates each leaf's
   segment and reads its `marker=` line, so batching loses no attribution. If no
   delimiters are present (a baked `/usr/local/bin/pks-autorun.sh` older than the
   delimiters; run `make disk` to refresh it), the Nth marker is attributed to the
   Nth leaf, which holds because the leaves always run in the same order.

The per-leaf transcripts of the old model (`sec/<leaf>/raw-{off,on}.log`) are no
longer produced; the only transcripts are `sec/raw-off.log` and `sec/raw-on.log`.

The axis runs under either substrate via the executor contract: `EXECUTOR=qemu`
(QEMU/KVM guest, default on a dev box) or `EXECUTOR=baremetal` (native on a booted
PKS host). See the top-level README for substrate selection.

---

## Target Preparation & Marker Verification Protocol

Each exploit leaf follows an identical five-step lifecycle:
1. **Target Preparation**: Writes a known sentinel marker (e.g. `PKS_CLEAN_MARKER_...`) into `/mnt/protected/victim_file`.
2. **Page-Cache Synchronization**: Invokes `sync` and flushes the page cache via `echo 3 > /proc/sys/vm/drop_caches` to force the kernel to re-read from physical storage upon next access.
3. **PoC Execution**: Executes the unprivileged PoC under `testuser` credentials. Interactive shells (`execlp("/bin/bash")`, `su`) are patched out to support headless automated benchmarking.
4. **Memory & Disk Inspection**: Inspects the first 256 bytes of `/mnt/protected/victim_file`. If the clean marker persists, the outcome is recorded as `marker=intact`; if overwritten, `marker=altered`.
5. **Crash & Panic Harvesting**: The host aggregator parses the transcript (QEMU
serial, or `/dev/kmsg` on bare metal). If an unexpected kernel panic/oops occurs
matching `PKS_PANIC_REGEX`, the outcome is recorded as `fail_closed_panic` and
evaluated as `verdict=FAIL` — with the stateless handler the kernel is expected to
neutralize in place and survive, so a panic is a regression, not a pass. Lines
forwarded from userspace (tagged `pks-autorun.sh[PID]:`) are excluded before the
match, so a PoC's own output (e.g. a `BUG:` banner) is never mistaken for a kernel
panic.

### Verdict Resolution & Pass Criteria

Verdicts are strictly evaluated by [`sec/run.sh`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec/run.sh):
- **Baseline Mode (`pcache_pks=off`)**: The exploit must alter the victim file (`marker=altered`) to confirm that the vulnerability is operational. An intact marker under `off` indicates the exploit failed to trigger, invalidating the negative control, and is evaluated strictly as `FAIL`.
- **Mitigated Mode (`pcache_pks=on`)**: The exploit must be neutralized in place, preserving the victim data (`marker=intact`). An altered marker indicates security mitigation failure and is scored as `FAIL`.
- **Panic & Crash Policy**: Any kernel oops, panic, or fault matching `PKS_PANIC_REGEX` sets `outcome=fail_closed_panic` and evaluates to `verdict=FAIL`.

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
 88-col banner  per-mode/leaf  Summary Table      sec/raw-{off,on}.log           sec/result.csv
from sec/run.sh from sec/run.sh from sec/run.sh (serial or /dev/kmsg)         (sole structured log)
```

1. **Terminal Console**: Driven entirely by [`sec/run.sh`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec/run.sh). An 88-column header opens the run, followed by per-leaf live execution logs. The summary footer displays side-by-side comparison tables between `off` and `on` modes.
2. **Persistent Storage**: All structured test records are stored strictly in [`sec/result.csv`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec/result.csv). No intermediate or leaf `result.log` files are created.
3. **Raw Transcripts**: One complete transcript per mode is preserved in `sec/raw-off.log` and `sec/raw-on.log` (all three leaves, delimited by `### PKS-LEAF <leaf>`) for post-run fault analysis.

---

## Result CSV Schema

The single output log [`sec/result.csv`](file:///Users/meilan/Documents/大学/学部卒論/pks-thesis-env/sec/result.csv) follows this structure:

```csv
node,variant,verdict,outcome
copy-fail,off,PASS,altered
copy-fail,on,PASS,intact
dirty-frag,off,PASS,altered
dirty-frag,on,PASS,intact
fragnesia,off,PASS,altered
fragnesia,on,PASS,intact
sec,all,PASS,passed=6_failed=0
```
