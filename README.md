# PKS Page-Cache Protection Evaluation Testbed (`pks-thesis-env`)

A reproducible, modular testbed for evaluating Supervisor Protection Keys (PKS)
page-cache isolation in the Linux kernel. It builds three guest kernels,
provisions a persistent Debian image, and runs three evaluation axes
(compliance, security, performance) headlessly under QEMU, **harvesting every
verdict from observed guest behaviour — nothing is hardcoded or simulated.**

## Layout: a self-similar tree

Every node is a directory with a `run.sh` and a generated `result.log`.

```
pks-thesis-env/
├── Makefile          # 5 verbs: build, disk, test, sec, perf
├── config.mk         # kernel paths, disk sizes, SMP/MEM, EXECUTOR
├── common.sh         # logging + the STATUS contract + harvest/rollup helpers
├── preflight.sh      # deps + substrate detection + provenance
├── configs/          # kconfig fragments: common, sec, perf, control
├── exec/             # substrate adapters: qemu.sh (now), baremetal.sh (stub)
├── guest/            # in-guest autorun.sh + autorun.service
├── build/  run.sh  result.log   {control,sec,perf}/run.sh   # 3 kernels
├── disk/   run.sh  result.log                               # provision + autorun
├── test/   run.sh  result.log   {pks-unit,sanity,fsx,pjd}/  # compliance
├── sec/    run.sh  result.log   {copy-fail,dirty-frag,fragnesia}/  # exploits
├── perf/   run.sh  result.log   {fio,concurrency,sqlite}/ + analyze.py
├── results/  raw/ (timestamped transcripts + JSON) + data/ (CSVs) + <verb>.log
└── tools/plotting/   # offline figures/TOST, consumes results/data/perf_summary.csv
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
serial transcript, harvests the leaf STATUS lines from it, writes each leaf's
`result.log`, and appends a rollup line to its own `result.log` — exiting nonzero
if any child failed. Two artifacts are kept, never conflated: `result.log`
(parsed, latest, rolled up) and `results/raw/**` (timestamped transcripts + JSON).

Because the transport is the **live serial stream**, a fail-closed kernel panic
(the intended `on` outcome for the softirq/workqueue exploits) is captured before
the VM dies. `classify_sec()` resolves a security leaf as: a final STATUS wins;
otherwise a PKS-attributable panic (`PKS_PANIC_REGEX` + `PKS_ACTIVE_REGEX`, both
overridable in `config.mk`) is a neutralization; anything else is an inconclusive
`FAIL`. Verdicts are always observations, never functions of the input flag.

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
CPU, QEMU version and substrate to `results/raw/preflight.json`. The workload tree
and the STATUS contract are substrate-agnostic: moving to a PKS-capable server is a
one-line `EXECUTOR` change (implement `exec/baremetal.sh` against the same
contract) with zero changes to `build/ test/ sec/ perf/`.

## Kernel builds are deterministic and preserved

Each kernel is `defconfig` + `kvm_guest.config` + the checked-in fragments in
`configs/` merged via `scripts/kconfig/merge_config.sh`. Cleanup targets never
touch the external kernel build trees (the preservation invariant).
