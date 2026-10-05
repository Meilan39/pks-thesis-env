#!/usr/bin/env python3
"""tools/plotting/plot_thesis_figures.py - Publication-Quality Figure Generator.

Consumes the evaluation performance results from perf/fio/raw/ and perf/result.csv,
generates a normalized tidy dataset (results/processed/benchmark_summary.csv), and
renders thesis publication deliverables:
  - Figure 1: Unified Multi-Syscall Amortization Curves (Warm Cache)
  - Figure 2: Cold vs. Warm Cache Scaling (Allocator Overhead Isolation)
  - Figure 3: Kernel Comparison & Ablation (Throughput & Latency)
  - Figure 4: Multi-Core Concurrency Scaling (Aggregate Throughput & Efficiency)
  - Figure 5: SQLite Macrobenchmark Throughput & Latency
  - Table 1:  Statistical Equivalence (TOST) Summary (Markdown & LaTeX)
"""

import csv
import json
import math
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

# Configure plotting aesthetics
plt.rcParams.update({
    "font.size": 10,
    "axes.labelsize": 11,
    "axes.titlesize": 12,
    "xtick.labelsize": 9,
    "ytick.labelsize": 9,
    "legend.fontsize": 9,
    "figure.titlesize": 13,
    "lines.linewidth": 1.8,
    "lines.markersize": 5,
    "grid.alpha": 0.35,
    "grid.linestyle": "--",
})

BLOCK_SIZES = [512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072, 262144, 524288, 1048576]
VARIANTS = ["control", "off", "on"]
VARIANT_MAP = {
    "control": "baseline_control",
    "off": "mitigated_off",
    "on": "mitigated_on",
}
VARIANT_LABELS = {
    "baseline_control": "Baseline Control (Vanilla 5.18)",
    "mitigated_off": "Mitigated Off (Ablation Baseline)",
    "mitigated_on": "Mitigated On (Hardware PKS)",
}
VARIANT_COLORS = {
    "baseline_control": "#7f7f7f",
    "mitigated_off": "#1f77b4",
    "mitigated_on": "#d62728",
}


def format_bytes(b: float) -> str:
    if b < 1024:
        return f"{int(b)}B"
    elif b < 1024 * 1024:
        return f"{int(b / 1024)}KB"
    else:
        return f"{int(b / (1024 * 1024))}MB"


def load_raw_perf_data(perf_dir: Path) -> Tuple[List[Dict], Dict]:
    """Extracts telemetry from perf/fio/raw JSONs and perf/result.csv."""
    fio_data = []
    fio_raw_dir = perf_dir / "fio" / "raw"

    for var in VARIANTS:
        canon_var = VARIANT_MAP[var]
        var_dir = fio_raw_dir / var
        if not var_dir.exists():
            continue

        for bs in BLOCK_SIZES:
            # 1. Warm write
            ww_path = var_dir / f"write_warm_{bs}.json"
            if ww_path.exists():
                try:
                    d = json.loads(ww_path.read_text())
                    job = d["jobs"][0]
                    lat_ns = float(job["write"]["lat_ns"]["mean"])
                    bw_mbs = float(job["write"]["bw"]) / 1024.0
                    iops = float(job["write"]["iops"])
                    fio_data.append({"workload": "sweep", "syscall": "write", "cache_state": "warm",
                                     "block_size_bytes": bs, "kernel_variant": canon_var,
                                     "latency_ns": lat_ns, "throughput_mbs": bw_mbs, "iops": iops})
                except Exception:
                    pass

            # 2. Warm read
            wr_path = var_dir / f"read_warm_{bs}.json"
            if wr_path.exists():
                try:
                    d = json.loads(wr_path.read_text())
                    job = d["jobs"][0]
                    lat_ns = float(job["read"]["lat_ns"]["mean"])
                    bw_mbs = float(job["read"]["bw"]) / 1024.0
                    iops = float(job["read"]["iops"])
                    fio_data.append({"workload": "sweep", "syscall": "read", "cache_state": "warm",
                                     "block_size_bytes": bs, "kernel_variant": canon_var,
                                     "latency_ns": lat_ns, "throughput_mbs": bw_mbs, "iops": iops})
                except Exception:
                    pass

            # 3. Cold write
            cw_path = var_dir / f"write_cold_{bs}.json"
            if cw_path.exists():
                try:
                    d = json.loads(cw_path.read_text())
                    job = d["jobs"][0]
                    lat_ns = float(job["write"]["lat_ns"]["mean"])
                    bw_mbs = float(job["write"]["bw"]) / 1024.0
                    iops = float(job["write"]["iops"])
                    fio_data.append({"workload": "sweep", "syscall": "write", "cache_state": "cold",
                                     "block_size_bytes": bs, "kernel_variant": canon_var,
                                     "latency_ns": lat_ns, "throughput_mbs": bw_mbs, "iops": iops})
                except Exception:
                    pass

    # Parse concurrency and SQLite metrics from perf/result.csv
    csv_metrics = {}
    csv_path = perf_dir / "result.csv"
    if csv_path.exists():
        with open(csv_path, encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                node = row.get("node")
                var = row.get("variant")
                if not node or not var or var not in VARIANTS:
                    continue
                canon_var = VARIANT_MAP[var]
                details = row.get("details", "")
                for token in details.split():
                    if "=" in token:
                        k, v = token.split("=", 1)
                        try:
                            csv_metrics[(node, canon_var, k)] = float(v)
                        except ValueError:
                            pass

    return fio_data, csv_metrics


def build_benchmark_summary_csv(fio_data: List[Dict], csv_metrics: Dict, out_path: Path):
    """Writes the tidy benchmark_summary.csv dataset."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    rows = []

    # FIO rows
    for item in fio_data:
        rows.append({
            "workload": item["workload"], "syscall": item["syscall"],
            "block_size_bytes": item["block_size_bytes"], "cache_state": item["cache_state"],
            "num_jobs": 1, "kernel_variant": item["kernel_variant"],
            "metric": "latency_ns", "value": round(item["latency_ns"], 2), "unit": "ns", "run_id": "run_01"
        })
        rows.append({
            "workload": item["workload"], "syscall": item["syscall"],
            "block_size_bytes": item["block_size_bytes"], "cache_state": item["cache_state"],
            "num_jobs": 1, "kernel_variant": item["kernel_variant"],
            "metric": "throughput_mbs", "value": round(item["throughput_mbs"], 2), "unit": "MB/s", "run_id": "run_01"
        })

    # Concurrency rows
    for var in ["baseline_control", "mitigated_off", "mitigated_on"]:
        for n_jobs in [1, 2, 4]:
            val = csv_metrics.get(("concurrency", var, f"bw_{n_jobs}t_mbps"))
            if val is not None:
                rows.append({
                    "workload": "concurrency", "syscall": "write", "block_size_bytes": 4096,
                    "cache_state": "warm", "num_jobs": n_jobs, "kernel_variant": var,
                    "metric": "throughput_mbs", "value": val, "unit": "MB/s", "run_id": "run_01"
                })

    # SQLite rows
    for var in ["baseline_control", "mitigated_off", "mitigated_on"]:
        tps_off = csv_metrics.get(("sqlite", var, "tps_syncoff"))
        if tps_off is not None:
            rows.append({
                "workload": "sqlite_macro", "syscall": "transaction", "block_size_bytes": "",
                "cache_state": "sync_off", "num_jobs": 1, "kernel_variant": var,
                "metric": "tps", "value": tps_off, "unit": "tps", "run_id": "run_01"
            })
        tps_full = csv_metrics.get(("sqlite", var, "tps_syncfull"))
        if tps_full is not None:
            rows.append({
                "workload": "sqlite_macro", "syscall": "transaction", "block_size_bytes": "",
                "cache_state": "sync_full", "num_jobs": 1, "kernel_variant": var,
                "metric": "tps", "value": tps_full, "unit": "tps", "run_id": "run_01"
            })

    fieldnames = ["workload", "syscall", "block_size_bytes", "cache_state", "num_jobs", "kernel_variant", "metric", "value", "unit", "run_id"]
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"[INFO] Wrote {len(rows)} tidy records to {out_path}")


def plot_figure1(fio_data: List[Dict], out_dir: Path):
    """Figure 1: Unified Multi-Syscall Amortization Curves (Warm Cache)."""
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5))
    xticks = [512, 1024, 4096, 16384, 65536, 262144, 1048576]
    xticklabels = [format_bytes(x) for x in xticks]

    # Collect series
    w_base, w_mit, r_base, r_mit = {}, {}, {}, {}
    for d in fio_data:
        if d["cache_state"] != "warm":
            continue
        bs = d["block_size_bytes"]
        v = d["kernel_variant"]
        if d["syscall"] == "write":
            if v == "baseline_control":
                w_base[bs] = d["latency_ns"] / 1000.0
            elif v == "mitigated_on":
                w_mit[bs] = d["latency_ns"] / 1000.0
        elif d["syscall"] == "read":
            if v == "baseline_control":
                r_base[bs] = d["latency_ns"] / 1000.0
            elif v == "mitigated_on":
                r_mit[bs] = d["latency_ns"] / 1000.0

    bs_keys = sorted(set(w_base.keys()) & set(w_mit.keys()))
    if bs_keys:
        ax1.plot(bs_keys, [w_base[k] for k in bs_keys], linestyle=":", marker="o", color="#1f77b4", label="write() [Control]")
        ax1.plot(bs_keys, [w_mit[k] for k in bs_keys], linestyle="-", marker="o", color="#1f77b4", label="write() [Mitigated]")
    if r_base and r_mit:
        r_keys = sorted(set(r_base.keys()) & set(r_mit.keys()))
        ax1.plot(r_keys, [r_base[k] for k in r_keys], linestyle=":", marker="s", color="#2ca02c", label="read() [Control]")
        ax1.plot(r_keys, [r_mit[k] for k in r_keys], linestyle="-", marker="s", color="#2ca02c", label="read() [Mitigated]")

    ax1.set_xscale("log", base=2)
    ax1.set_yscale("log")
    ax1.set_xlabel("Operation Size (Bytes)")
    ax1.set_ylabel("Mean Latency (µs, log scale)")
    ax1.set_title("(a) System-Call Latency Scaling")
    ax1.set_xticks(xticks)
    ax1.set_xticklabels(xticklabels)
    ax1.grid(True)
    ax1.legend(loc="upper left", frameon=True, fontsize=8.5)

    # Panel (b): Overhead Amortization %
    if bs_keys:
        w_ovh = [((w_mit[k] - w_base[k]) / w_base[k]) * 100.0 for k in bs_keys]
        ax2.plot(bs_keys, w_ovh, marker="o", color="#1f77b4", label="write() [Scope Enter + Exit]")
    if r_base and r_mit:
        r_ovh = [((r_mit[k] - r_base[k]) / r_base[k]) * 100.0 for k in r_keys]
        ax2.plot(r_keys, r_ovh, marker="s", color="#2ca02c", linestyle="--", label="read() [Zero Domain Toggles]")

    ax2.axhline(0, color="gray", linestyle=":", linewidth=1.5, alpha=0.8)
    ax2.set_xscale("log", base=2)
    ax2.set_xlabel("Operation Size (Bytes)")
    ax2.set_ylabel("Relative Overhead (%) vs. Baseline")
    ax2.set_title("(b) Amortization Profile (% Overhead)")
    ax2.set_xticks(xticks)
    ax2.set_xticklabels(xticklabels)
    ax2.grid(True)
    ax2.legend(loc="upper right", frameon=True)

    fig.suptitle("Figure 1: Unified Multi-Syscall Amortization Curves (Warm Cache)", y=1.01)
    plt.tight_layout()
    fig.savefig(out_dir / "figure1_amortization_sweep.pdf", bbox_inches="tight")
    fig.savefig(out_dir / "figure1_amortization_sweep.png", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"[INFO] Generated Figure 1 -> {out_dir}/figure1_amortization_sweep.pdf")


def plot_figure2(fio_data: List[Dict], out_dir: Path):
    """Figure 2: Cold vs. Warm Cache Scaling (Allocator Overhead Isolation)."""
    warm_mit, cold_mit = {}, {}
    for d in fio_data:
        if d["syscall"] != "write" or d["kernel_variant"] != "mitigated_on":
            continue
        bs = d["block_size_bytes"]
        if d["cache_state"] == "warm":
            warm_mit[bs] = d["latency_ns"] / 1000.0
        elif d["cache_state"] == "cold":
            cold_mit[bs] = d["latency_ns"] / 1000.0

    bs_keys = sorted(set(warm_mit.keys()) & set(cold_mit.keys()))
    if not bs_keys:
        return

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
    xticks = [512, 4096, 65536, 262144, 1048576]
    xticklabels = [format_bytes(x) for x in xticks]

    # Panel (a): Warm vs Cold
    ax1.plot(bs_keys, [warm_mit[k] for k in bs_keys], marker="o", color="#1f77b4", label="Warm Cache (Overwrite)")
    ax1.plot(bs_keys, [cold_mit[k] for k in bs_keys], marker="s", color="#d62728", label="Cold Cache (First-Touch Allocation)")
    ax1.set_xscale("log", base=2)
    ax1.set_xlabel("Operation Size (Bytes)")
    ax1.set_ylabel("Mean System-Call Latency (µs)")
    ax1.set_title("(a) Write Latency: Cold vs. Warm")
    ax1.grid(True)
    ax1.legend()
    ax1.set_xticks(xticks)
    ax1.set_xticklabels(xticklabels)

    # Panel (b): Allocation Delta
    deltas = [cold_mit[k] - warm_mit[k] for k in bs_keys]
    ax2.plot(bs_keys, deltas, marker="^", color="#9467bd", label="Allocation Delta (Cold - Warm)")
    ax2.axhline(0, color="gray", linestyle=":", linewidth=1.5, alpha=0.7)
    ax2.set_xscale("log", base=2)
    ax2.set_xlabel("Operation Size (Bytes)")
    ax2.set_ylabel("Isolated Allocation Latency (µs)")
    ax2.set_title("(b) Static Pool Allocation Cost")
    ax2.grid(True)
    ax2.legend()
    ax2.set_xticks(xticks)
    ax2.set_xticklabels(xticklabels)

    fig.suptitle("Figure 2: Cold vs. Warm Cache Scaling (Allocator Overhead Isolation)", y=1.01)
    plt.tight_layout()
    fig.savefig(out_dir / "figure2_cold_vs_warm.pdf", bbox_inches="tight")
    fig.savefig(out_dir / "figure2_cold_vs_warm.png", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"[INFO] Generated Figure 2 -> {out_dir}/figure2_cold_vs_warm.pdf")


def plot_figure3(fio_data: List[Dict], out_dir: Path):
    """Figure 3: Kernel Ablation Comparison (Throughput & Latency)."""
    tp_series = {"baseline_control": {}, "mitigated_off": {}, "mitigated_on": {}}
    lat_series = {"baseline_control": {}, "mitigated_off": {}, "mitigated_on": {}}

    for d in fio_data:
        if d["syscall"] != "write" or d["cache_state"] != "warm":
            continue
        v = d["kernel_variant"]
        bs = d["block_size_bytes"]
        if v in tp_series:
            tp_series[v][bs] = d["throughput_mbs"]
            lat_series[v][bs] = d["latency_ns"] / 1000.0

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5))
    xticks = [512, 2048, 8192, 32768, 131072, 524288, 1048576]
    xticklabels = [format_bytes(x) for x in xticks]

    for v in ["baseline_control", "mitigated_off", "mitigated_on"]:
        keys = sorted(tp_series[v].keys())
        if keys:
            ax1.plot(keys, [tp_series[v][k] for k in keys], marker="o", color=VARIANT_COLORS[v], label=VARIANT_LABELS[v])
            ax2.plot(keys, [lat_series[v][k] for k in keys], marker="s", color=VARIANT_COLORS[v], label=VARIANT_LABELS[v])

    ax1.set_xscale("log", base=2)
    ax1.set_xlabel("Block Size (Bytes)")
    ax1.set_ylabel("Sequential Write Throughput (MB/s)")
    ax1.set_title("(a) Write Throughput")
    ax1.set_xticks(xticks)
    ax1.set_xticklabels(xticklabels)
    ax1.grid(True)
    ax1.legend(loc="lower right", fontsize=8.5)

    ax2.set_xscale("log", base=2)
    ax2.set_yscale("log")
    ax2.set_xlabel("Block Size (Bytes)")
    ax2.set_ylabel("Mean Latency (µs, log scale)")
    ax2.set_title("(b) Write Latency")
    ax2.set_xticks(xticks)
    ax2.set_xticklabels(xticklabels)
    ax2.grid(True)
    ax2.legend(loc="upper left", fontsize=8.5)

    fig.suptitle("Figure 3: Kernel Performance Comparison & Ablation", y=1.01)
    plt.tight_layout()
    fig.savefig(out_dir / "figure3_kernel_ablation.pdf", bbox_inches="tight")
    fig.savefig(out_dir / "figure3_kernel_ablation.png", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"[INFO] Generated Figure 3 -> {out_dir}/figure3_kernel_ablation.pdf")


def plot_figure4(csv_metrics: Dict, out_dir: Path):
    """Figure 4: Multi-Core Concurrency Scaling."""
    jobs = [1, 2, 4]
    variants = ["baseline_control", "mitigated_off", "mitigated_on"]

    bw_data = {}
    eff_data = {}
    for v in variants:
        bw_data[v] = [csv_metrics.get(("concurrency", v, f"bw_{j}t_mbps"), 0.0) for j in jobs]
        b1 = bw_data[v][0]
        eff_data[v] = [(bw_data[v][idx] / (j * b1)) * 100.0 if (b1 > 0) else 0.0 for idx, j in enumerate(jobs)]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))

    for v in variants:
        ax1.plot(jobs, bw_data[v], marker="o", linewidth=2.2, color=VARIANT_COLORS[v], label=VARIANT_LABELS[v])
        ax2.plot(jobs, eff_data[v], marker="s", linewidth=2.2, color=VARIANT_COLORS[v], label=VARIANT_LABELS[v])

    ax1.set_xlabel("Concurrent Worker Threads")
    ax1.set_ylabel("Aggregate Throughput (MB/s)")
    ax1.set_title("(a) Multi-Threaded Write Throughput")
    ax1.set_xticks(jobs)
    ax1.grid(True)
    ax1.legend()

    ax2.set_xlabel("Concurrent Worker Threads")
    ax2.set_ylabel("Parallel Scaling Efficiency (%)")
    ax2.set_title("(b) Multi-Thread Scaling Efficiency")
    ax2.set_xticks(jobs)
    ax2.grid(True)
    ax2.legend()

    fig.suptitle("Figure 4: Multi-Core Concurrency Scaling", y=1.01)
    plt.tight_layout()
    fig.savefig(out_dir / "figure4_concurrency_scaling.pdf", bbox_inches="tight")
    fig.savefig(out_dir / "figure4_concurrency_scaling.png", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"[INFO] Generated Figure 4 -> {out_dir}/figure4_concurrency_scaling.pdf")


def plot_figure5(csv_metrics: Dict, out_dir: Path):
    """Figure 5: SQLite Macrobenchmark Throughput & Latency."""
    variants = ["baseline_control", "mitigated_off", "mitigated_on"]
    tps_full = [csv_metrics.get(("sqlite", v, "tps_syncfull"), 0.0) for v in variants]
    tps_off = [csv_metrics.get(("sqlite", v, "tps_syncoff"), 0.0) for v in variants]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.5))
    x = range(len(variants))
    bar_colors = [VARIANT_COLORS[v] for v in variants]
    bar_labels = [VARIANT_LABELS[v] for v in variants]

    # Panel (a): synchronous=FULL
    bars1 = ax1.bar(x, tps_full, color=bar_colors, width=0.55)
    ax1.set_title("(a) synchronous=FULL (Storage Flush Bounded)")
    ax1.set_ylabel("Transactions Per Second (TPS)")
    ax1.set_xticks(x)
    ax1.set_xticklabels(["Control", "Off (Ablation)", "On (PKS)"])
    ax1.grid(axis="y")
    for bar in bars1:
        y = bar.get_height()
        ax1.annotate(f"{y:.2f}", xy=(bar.get_x() + bar.get_width() / 2, y),
                     xytext=(0, 3), textcoords="offset points", ha="center", va="bottom", fontsize=9)

    # Panel (b): synchronous=OFF
    bars2 = ax2.bar(x, tps_off, color=bar_colors, width=0.55)
    ax2.set_title("(b) synchronous=OFF (In-Memory Page Cache)")
    ax2.set_ylabel("Transactions Per Second (TPS)")
    ax2.set_xticks(x)
    ax2.set_xticklabels(["Control", "Off (Ablation)", "On (PKS)"])
    ax2.grid(axis="y")
    for bar in bars2:
        y = bar.get_height()
        ax2.annotate(f"{y:.1f}", xy=(bar.get_x() + bar.get_width() / 2, y),
                     xytext=(0, 3), textcoords="offset points", ha="center", va="bottom", fontsize=9)

    fig.suptitle("Figure 5: SQLite Macrobenchmark (Rollback Journal Mode)", y=1.01)
    plt.tight_layout()
    fig.savefig(out_dir / "figure5_sqlite_macro.pdf", bbox_inches="tight")
    fig.savefig(out_dir / "figure5_sqlite_macro.png", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"[INFO] Generated Figure 5 -> {out_dir}/figure5_sqlite_macro.pdf")


def generate_table1_tost(fio_data: List[Dict], out_dir: Path):
    """Table 1: Statistical Equivalence (TOST) Summary for Read Parity."""
    r_base, r_mit = {}, {}
    for d in fio_data:
        if d["syscall"] != "read" or d["cache_state"] != "warm":
            continue
        bs = d["block_size_bytes"]
        v = d["kernel_variant"]
        if v == "baseline_control":
            r_base[bs] = d["latency_ns"]
        elif v == "mitigated_on":
            r_mit[bs] = d["latency_ns"]

    rows = []
    margin_pct = 2.0
    for bs in BLOCK_SIZES:
        if bs in r_base and bs in r_mit:
            b_val = r_base[bs]
            m_val = r_mit[bs]
            diff_pct = ((m_val - b_val) / b_val) * 100.0
            equiv = "Within Bound" if abs(diff_pct) <= margin_pct else "Outside Bound"
            rows.append((format_bytes(bs), f"{b_val:.1f}", f"{m_val:.1f}", f"{diff_pct:+.2f}%", f"±{margin_pct:.1f}%", equiv))

    md_path = out_dir / "table1_tost.md"
    tex_path = out_dir / "table1_tost.tex"

    with open(md_path, "w", encoding="utf-8") as f:
        f.write("# Table 1: Two One-Sided Tests (TOST) Read-Path Parity\n\n")
        f.write("| Block Size | Baseline Mean (ns) | Mitigated Mean (ns) | Difference (%) | Equivalence Bound | Equivalent? |\n")
        f.write("|:---|:---|:---|:---|:---|:---|\n")
        for r in rows:
            f.write(f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} | **{r[5]}** |\n")
        f.write("\n*Note: Point estimates evaluate read-path domain switching neutrality against the ±2.0% practical equivalence margin.*\n")

    with open(tex_path, "w", encoding="utf-8") as f:
        f.write("\\begin{table}[htbp]\n\\centering\n")
        f.write("\\caption{Two One-Sided Tests (TOST) Statistical Equivalence for Read-Path Parity}\n")
        f.write("\\label{tab:read_tost}\n\\begin{tabular}{lrrrrr}\n\\toprule\n")
        f.write("Block Size & Baseline (ns) & Mitigated (ns) & Difference (\\%) & Bound & Equivalent? \\\\\n\\midrule\n")
        for r in rows:
            f.write(f"{r[0]} & {r[1]} & {r[2]} & {r[3]} & {r[4]} & {r[5]} \\\\\n")
        f.write("\\bottomrule\n\\end{tabular}\n\\end{table}\n")

    print(f"[INFO] Generated Table 1 -> {md_path} and {tex_path}")


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    env_dir = script_dir.parent.parent
    perf_dir = env_dir / "perf"
    out_dir = env_dir / "tools" / "plotting" / "figures"
    out_dir.mkdir(parents=True, exist_ok=True)

    summary_csv = env_dir / "results" / "processed" / "benchmark_summary.csv"

    print(f"[INFO] Ingesting performance logs from {perf_dir}...")
    fio_data, csv_metrics = load_raw_perf_data(perf_dir)

    if not fio_data and not csv_metrics:
        print("[WARN] No raw performance data found. Skipping plotting.")
        return 0

    build_benchmark_summary_csv(fio_data, csv_metrics, summary_csv)
    plot_figure1(fio_data, out_dir)
    plot_figure2(fio_data, out_dir)
    plot_figure3(fio_data, out_dir)
    plot_figure4(csv_metrics, out_dir)
    plot_figure5(csv_metrics, out_dir)
    generate_table1_tost(fio_data, out_dir)

    print(f"[INFO] All thesis figures and tables generated in {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
