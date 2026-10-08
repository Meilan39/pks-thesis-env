# PKS Page-Cache Protection Evaluation Testbed (`pks-thesis-env`)

A reproducible, modular testbed for evaluating Supervisor Protection Keys (PKS)
page-cache isolation in the Linux kernel. It builds three guest kernels,
provisions a persistent Debian image, and runs three evaluation axes
(compliance, security, performance) headlessly under QEMU, **harvesting every
verdict from observed guest behaviour — nothing is hardcoded or simulated.**

## Layout: a self-similar tree

Every evaluation axis provides a self-contained runner (`run.sh`), comprehensive reviewer documentation (`README.md`), and exports structured records strictly into an in-tree `result.csv`.

```text
pks-thesis-env/
├── Makefile          # 5 verbs: build, disk, test, sec, perf
├── config.mk         # kernel paths, disk sizes, SMP/MEM, EXECUTOR
├── common.sh         # logging, console report helpers, and the STATUS contract
├── preflight.sh      # deps + substrate detection + provenance
├── configs/          # kconfig fragments: common, sec, perf, control
├── exec/             # substrate adapters: qemu.sh (now), baremetal.sh (stub)
├── guest/            # in-guest autorun.sh + autorun.service
├── build/            # kernel compilation: control, sec, perf
├── disk/             # debian image provisioning + autorun setup
├── test/             # Compliance axis: {fsx, pks-unit, sanity} -> test/result.csv
├── sec/              # Security axis: {copy-fail, dirty-frag, fragnesia} -> sec/result.csv
├── perf/             # Performance axis: {fio, concurrency, sqlite} -> perf/result.csv + analyze.py
├── results/          # Publication datasets: results/data/perf_summary.csv
└── tools/plotting/   # Offline thesis figure generation from results/data/
```

Note the deliberate, documented name reuse: `build/sec/` **builds the diagnostic
kernel**; top-level `sec/` **runs the exploits**.

## Quick start

```bash
make build      # compile control, sec, perf kernels (external trees; see config.mk)
make disk       # provision images/disk.img ONCE (skipped if it exists) + install autorun
make test       # compliance suite, off & on
make sec        # exploit neutralization, off & on
make perf       # fio / concurrency / sqlite across control, off, on

make run-qemu VARIANT=perf MODE=on   # interactive serial console for debugging
```

Granular runs: call any subtree's `run.sh` directly, e.g. `./sec/copy-fail/run.sh`,
`./perf/fio/run.sh`, `./build/sec/run.sh`. This replaces the old flat list of
per-target Makefile rules.

## The node contract (how results flow up)

A **leaf** `run.sh` performs its work and prints, on stdout, one line per result:

```
STATUS node=<name> variant=<control|off|on> verdict=<PASS|FAIL|NEUTRALIZED|VULNERABLE|PENDING> [k=v]...
```

`PASS`/`NEUTRALIZED` are passing; `FAIL`/`VULNERABLE` are failing; `PENDING` is
emitted just before a possibly-fatal step and resolved later by the host.

An **aggregator** `run.sh` boots the guest via `exec/$(EXECUTOR).sh`, captures the
serial transcript, harvests the leaf STATUS lines directly, prints a structured
3-tier console report (88-col banner, live per-variant stream, and summary table footer),
and appends structured rows to its axis `result.csv` — exiting nonzero if any child failed.

All intermediate `result.log` files and raw JSONs (with the exception of `fio` multi-block
size curves in `perf/fio/raw/`) are eliminated:
- **Terminal Console**: Live 3-tier formatted stream.
- **Persistent Structured Records**: Solely in-tree `<axis>/result.csv` (`sec/result.csv`, `test/result.csv`, `perf/result.csv`).
- **Raw Transcripts**: Captured in `<axis>/raw-<variant>.log` for serial auditing.

Because the transport is the **live serial stream**, a fail-closed kernel panic
(the intended `on` outcome for the softirq/workqueue exploits) is captured before
the VM dies. Each security leaf echoes a `marker=intact|altered` line that
`sec/run.sh` resolves into an outcome: under `off`, an altered marker is the
expected real vulnerability (`PASS`); under `on`, a surviving marker or a
PKS-attributable panic (`PKS_PANIC_REGEX` + `PKS_ACTIVE_REGEX`, both overridable
via the environment) is a neutralization (`PASS`); anything else is an
inconclusive `FAIL`. Verdicts are always observations, never functions of the
input flag.

## Security causality

Each exploit leaf writes a unique marker to the victim file, drops caches to force
a real page-cache re-fault, runs the PoC, and compares the marker back:
- `off` → marker altered → `VULNERABLE` (proves the exploit is real);
- `on`, syscall context (copy-fail) → write trapped as `-EFAULT`, marker intact → `NEUTRALIZED`;
- `on`, softirq/workqueue context (dirty-frag, fragnesia) → unhandled supervisor
  fault → **kernel panic**; the faulting store never lands, so the panic itself
  (with PKS active) is the neutralization, harvested from the serial transcript.

## Substrate & provenance

`preflight.sh` detects `kvm-pks` / `kvm-nopks` / `tcg` and records host kernel,
CPU, QEMU version and substrate to `results/preflight.json`. The workload tree
and the STATUS contract are substrate-agnostic: moving to a PKS-capable server is a
one-line `EXECUTOR` change (implement `exec/baremetal.sh` against the same
contract) with zero changes to `build/ test/ sec/ perf/`.

## Kernel builds are deterministic and preserved

Each kernel is `defconfig` + `kvm_guest.config` + the checked-in fragments in
`configs/` merged via `scripts/kconfig/merge_config.sh`. Cleanup targets never
touch the external kernel build trees (the preservation invariant).
