# PKS Page-Cache Protection Evaluation Testbed (`pks-thesis-env`)

A reproducible, modular testbed for evaluating Supervisor Protection Keys (PKS)
page-cache isolation in the Linux kernel. It builds three guest kernels,
provisions a persistent Debian image, and runs three evaluation axes
(compliance, security, performance) headlessly — under QEMU/KVM **or natively on
a PKS-capable host** — **harvesting every verdict from observed behaviour;
nothing is hardcoded or simulated.**

## Layout: a self-similar tree

Every evaluation axis provides a self-contained runner (`run.sh`), comprehensive reviewer documentation (`README.md`), and exports structured records strictly into an in-tree `result.csv`.

```text
pks-thesis-env/
├── Makefile          # 5 verbs: build, disk, test, sec, perf
├── config.mk         # kernel paths, disk sizes, SMP/MEM, EXECUTOR, bare-metal vars
├── common.sh         # logging, console report helpers, STATUS contract, resolve_executor
├── preflight.sh      # deps + executor/substrate detection + provenance
├── configs/          # kconfig fragments: common, sec, perf, control, baremetal
├── exec/             # substrate adapters: qemu.sh + baremetal.sh (native PKS host)
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

## Choosing a substrate (QEMU vs bare metal)

`EXECUTOR` (in `config.mk`, default `auto`) selects the execution substrate; the
axes resolve it via `resolve_executor` in `common.sh`:

- `auto` → `baremetal` when the host is itself a booted PKS testbed kernel
  (CPU advertises `pks` **and** the running kernel is one of ours), else `qemu`.
  A stock kernel on PKS silicon, or any non-PKS host, falls back to `qemu`.
- `qemu` → QEMU guest adapter; uses `-cpu host -enable-kvm` when the host has
  KVM + hardware PKS (near-native MSR cost), otherwise TCG emulation.
- `baremetal` → runs the leaves natively on this PKS host for **zero-
  virtualization-overhead** numbers (see `exec/baremetal.sh`).

```bash
make perf                          # auto-detect (QEMU on a dev box)
sudo EXECUTOR=baremetal make sec   # run natively on a booted PKS host
make build BAREMETAL=1             # build kernels with real-hardware drivers
```

Bare-metal runs require: the host booted into the matching patched kernel/mode,
a dedicated evaluation partition `PROTECTED_DEV` (never the rootfs), and root.
A single boot serves one `(variant, mode)`; drive the full matrix by rebooting
into each config. See `context/benchmark-plan-6.md`.

## The node contract (how results flow up)

A **leaf** `run.sh` performs its work and prints, on stdout, one line per result:

```
STATUS node=<name> variant=<control|off|on> verdict=<PASS|FAIL|NEUTRALIZED|VULNERABLE|PENDING> [k=v]...
```

`PASS`/`NEUTRALIZED` are passing; `FAIL`/`VULNERABLE` are failing; `PENDING` is
emitted just before a possibly-fatal step and resolved later by the host.

An **aggregator** `run.sh` boots the guest via `exec/<executor>.sh` (the executor
is resolved from `EXECUTOR` — `auto` picks `baremetal` on a PKS host, else `qemu`),
captures the transcript, harvests the leaf STATUS lines directly, prints a structured
3-tier console report (88-col banner, live per-variant stream, and summary table footer),
and appends structured rows to its axis `result.csv` — exiting nonzero if any child failed.

All intermediate `result.log` files and raw JSONs (with the exception of `fio` multi-block
size curves in `perf/fio/raw/`) are eliminated:
- **Terminal Console**: Live 3-tier formatted stream.
- **Persistent Structured Records**: Solely in-tree `<axis>/result.csv` (`sec/result.csv`, `test/result.csv`, `perf/result.csv`).
- **Raw Transcripts**: Captured in `<axis>/raw-<variant>.log` for serial auditing.

The transport is the **live kernel/serial stream** (QEMU serial, or `/dev/kmsg`
on bare metal), so neutralization and any fault are captured as they happen. Each
security leaf echoes a `marker=intact|altered` line that `sec/run.sh` resolves into
an outcome: under `off`, an altered marker is the expected real vulnerability
(`PASS`); under `on`, a **surviving marker** is the expected in-place neutralization
(`PASS`). With the stateless fault handler the kernel neutralizes every vector in
place without crashing, so a panic/oops matching `PKS_PANIC_REGEX` is **not** a pass —
it is a regression scored `FAIL`. Verdicts are always observations, never functions
of the input flag.

## Security causality

Each exploit leaf writes a unique marker to the victim file, drops caches to force
a real page-cache re-fault, runs the PoC, and compares the marker back:
- `off` → marker altered → `VULNERABLE` (proves the exploit is real);
- `on`, syscall context (copy-fail) → unauthorized store trapped and the offending
  user task killed; marker intact → `NEUTRALIZED`;
- `on`, softirq/workqueue context (dirty-frag, fragnesia) → the stateless fault
  handler suppresses each stray store in place (advances past it) without crashing;
  the store never lands, so the marker stays intact → `NEUTRALIZED`. A kernel panic
  here is a regression (`FAIL`), not a pass.

## Substrate & provenance

`preflight.sh` resolves the executor and records it, the substrate
(`baremetal-pks` / `kvm-pks` / `kvm-nopks` / `tcg`), host kernel, CPU and QEMU
version to `results/preflight.json`. The workload tree and the STATUS contract are
substrate-agnostic: the only per-substrate code is the executor adapter. `exec/qemu.sh`
and `exec/baremetal.sh` both honour the same four-argument contract
(`<variant> <mode> <target> [transcript]`), so `build/ test/ sec/ perf/` are unchanged
across substrates — moving to a PKS server is an `EXECUTOR` change, nothing more.

## Kernel builds are deterministic and preserved

Each kernel is `defconfig` + `kvm_guest.config` + the checked-in fragments in
`configs/` merged via `scripts/kconfig/merge_config.sh`. Cleanup targets never
touch the external kernel build trees (the preservation invariant).
