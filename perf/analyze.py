#!/usr/bin/env python3
"""perf/analyze.py - Synthesize the performance summary from HARVESTED JSON.

Reads results/raw/json/<variant>/... produced by the perf leaves and computes
relative overhead of the mitigated kernel (on) against the baseline (control),
with the ablation (off) shown alongside. No values are hardcoded; a metric with
no data is written as empty. Usage: analyze.py <json_root> <out_csv>
"""
import csv
import json
import sys
from pathlib import Path

VARIANTS = ("control", "off", "on")


def load(path):
    try:
        return json.loads(Path(path).read_text())
    except Exception:
        return None


def fio_lat_us(root, variant, name, op):
    d = load(root / variant / "fio" / f"{name}.json")
    try:
        return d["jobs"][0][op]["lat_ns"]["mean"] / 1000.0
    except Exception:
        return None


def sqlite_tps(root, variant, mode):
    d = load(root / variant / f"sqlite_{mode}.json")
    try:
        return float(d["tps"])
    except Exception:
        return None


def overhead(base, on):
    if base is None or on is None or base == 0:
        return ""
    return f"{(on / base - 1.0) * 100:+.2f}%"


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "results/raw/json")
    out = Path(sys.argv[2] if len(sys.argv) > 2 else "results/data/perf_summary.csv")
    out.parent.mkdir(parents=True, exist_ok=True)

    metrics = [
        ("fio 4KB warm", "Write Lat (us)", lambda v: fio_lat_us(root, v, "write_warm_4096", "write")),
        ("fio 4KB warm", "Read Lat (us)",  lambda v: fio_lat_us(root, v, "read_warm_4096", "read")),
        ("fio 4KB cold", "Write Lat (us)", lambda v: fio_lat_us(root, v, "write_cold_4096", "write")),
        ("sqlite",       "Tx/s (sync=OFF)",  lambda v: sqlite_tps(root, v, "OFF")),
        ("sqlite",       "Tx/s (sync=FULL)", lambda v: sqlite_tps(root, v, "FULL")),
    ]

    rows = []
    for bench, metric, fn in metrics:
        vals = {v: fn(v) for v in VARIANTS}
        rows.append({
            "Benchmark": bench, "Metric": metric,
            "control": "" if vals["control"] is None else round(vals["control"], 2),
            "off":     "" if vals["off"] is None else round(vals["off"], 2),
            "on":      "" if vals["on"] is None else round(vals["on"], 2),
            "Overhead_vs_control": overhead(vals["control"], vals["on"]),
        })

    with out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["Benchmark", "Metric", "control", "off", "on", "Overhead_vs_control"])
        w.writeheader()
        w.writerows(rows)

    print("[analyze-perf] wrote", out)
    for r in rows:
        print(f"  {r['Benchmark']:<14} {r['Metric']:<16} "
              f"control={r['control']!s:<10} off={r['off']!s:<10} on={r['on']!s:<10} {r['Overhead_vs_control']}")


if __name__ == "__main__":
    main()
