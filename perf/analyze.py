#!/usr/bin/env python3
"""perf/analyze.py - Synthesize performance summary from perf/result.csv.

Reads perf/result.csv (with fallback to raw fio JSON distributions) and computes
relative overhead of the mitigated kernel (on) against the baseline (control),
with the ablation (off) shown alongside.
Usage: analyze.py <perf_dir> <out_csv>
"""
import csv
import json
import sys
from pathlib import Path

VARIANTS = ("control", "off", "on")


def parse_csv_metrics(perf_dir):
    csv_path = perf_dir / "result.csv"
    data = {}
    if not csv_path.exists():
        return data

    with open(csv_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            node = row.get("node")
            var = row.get("variant")
            if not node or not var or var not in VARIANTS:
                continue
            details = row.get("details", "")
            for token in details.split():
                if "=" in token:
                    parts = token.split("=", 1)
                    try:
                        data[(node, var, parts[0])] = float(parts[1])
                    except ValueError:
                        pass
    return data


def fio_lat_us_raw(perf_dir, variant, name, op):
    path = perf_dir / "fio" / "raw" / variant / f"{name}.json"
    try:
        d = json.loads(path.read_text())
        return d["jobs"][0][op]["lat_ns"]["mean"] / 1000.0
    except Exception:
        return None


def overhead(base, on):
    if base is None or on is None or base == 0:
        return ""
    return f"{(on / base - 1.0) * 100:+.2f}%"


def main():
    perf_dir = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    out = Path(sys.argv[2] if len(sys.argv) > 2 else "results/data/perf_summary.csv")
    out.parent.mkdir(parents=True, exist_ok=True)

    csv_data = parse_csv_metrics(perf_dir)

    def get_metric(node, var, key, fallback_fn=None):
        if (node, var, key) in csv_data:
            return csv_data[(node, var, key)]
        if fallback_fn:
            return fallback_fn(var)
        return None

    metrics = [
        ("fio 4KB warm", "Write Lat (us)",
         lambda v: get_metric("fio", v, "lat4k_warm_write_us",
                              lambda var: fio_lat_us_raw(perf_dir, var, "write_warm_4096", "write"))),
        ("fio 4KB warm", "Read Lat (us)",
         lambda v: get_metric("fio", v, "lat4k_warm_read_us",
                              lambda var: fio_lat_us_raw(perf_dir, var, "read_warm_4096", "read"))),
        ("fio 4KB cold", "Write Lat (us)",
         lambda v: get_metric("fio", v, "lat4k_cold_write_us",
                              lambda var: fio_lat_us_raw(perf_dir, var, "write_cold_4096", "write"))),
        ("sqlite", "Tx/s (sync=OFF)",
         lambda v: get_metric("sqlite", v, "tps_syncoff")),
        ("sqlite", "Tx/s (sync=FULL)",
         lambda v: get_metric("sqlite", v, "tps_syncfull")),
    ]

    rows = []
    for bench, metric, fn in metrics:
        vals = {v: fn(v) for v in VARIANTS}
        rows.append({
            "Benchmark": bench,
            "Metric": metric,
            "control": "" if vals["control"] is None else round(vals["control"], 2),
            "off": "" if vals["off"] is None else round(vals["off"], 2),
            "on": "" if vals["on"] is None else round(vals["on"], 2),
            "Overhead_vs_control": overhead(vals["control"], vals["on"]),
        })

    with out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["Benchmark", "Metric", "control", "off", "on", "Overhead_vs_control"])
        w.writeheader()
        w.writerows(rows)

    print("[analyze-perf] wrote", out)
    for r in rows:
        print(f"  {r['Benchmark']:<14} {r['Metric']:<16} "
              f"control={str(r['control']):<10} off={str(r['off']):<10} on={str(r['on']):<10} {r['Overhead_vs_control']}")


if __name__ == "__main__":
    main()
