#!/usr/bin/env python3
"""
tools/plotting/plot_thesis_figures.py - Publication-Quality Figure Generator.

Reads the normalized benchmark summary dataset (benchmark_summary.csv)
and generates thesis deliverables:
  - Figure 1: Unified Multi-Syscall Amortization Curves (Warm Cache)
  - Figure 2: Cold vs. Warm Cache Scaling (Allocator Overhead Isolation)
  - Figure 3: Kernel Comparison & Ablation (Throughput & Latency)
  - Figure 4: Multi-Core Concurrency Scaling (Aggregate Throughput & Latency)
  - Figure 5: SQLite Macrobenchmark Throughput & Latency
  - Table 1:  Statistical Equivalence (TOST) Summary
"""

import math
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Use non-interactive backend for headless plotting
import matplotlib
matplotlib.use("Agg")

try:
    import matplotlib.pyplot as plt
    import numpy as np
    import pandas as pd
    from scipy import stats
except ImportError as e:
    print(f"[ERROR] Required Python packages not found: {e}", file=sys.stderr)
    print("[INFO] Run: pip install -r tools/plotting/requirements.txt", file=sys.stderr)
    sys.exit(1)


# Plotting style configuration
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


def format_bytes(b: float) -> str:
    if b < 1024:
        return f"{int(b)}B"
    elif b < 1024 * 1024:
        return f"{int(b / 1024)}KB"
    else:
        return f"{int(b / (1024 * 1024))}MB"


def calculate_overhead(df: pd.DataFrame, syscall: str, cache_state: str = "warm", metric: str = "latency_ns") -> Optional[pd.DataFrame]:
    sub = df[(df["syscall"] == syscall) & (df["cache_state"] == cache_state) & (df["metric"] == metric)]
    if sub.empty:
        return None
    
    pivot_mean = sub.pivot_table(index="block_size_bytes", columns="kernel_variant", values="value", aggfunc="mean")
    if "baseline_control" not in pivot_mean.columns or "mitigated_on" not in pivot_mean.columns:
        return None
    
    pivot_mean["overhead_pct"] = ((pivot_mean["mitigated_on"] - pivot_mean["baseline_control"]) / pivot_mean["baseline_control"]) * 100.0
    
    pivot_sem = sub.pivot_table(index="block_size_bytes", columns="kernel_variant", values="value", aggfunc="sem")
    if "baseline_control" in pivot_sem.columns and "mitigated_on" in pivot_sem.columns and pivot_sem.notna().any().any():
        m = pivot_mean["mitigated_on"]
        b = pivot_mean["baseline_control"]
        sm = pivot_sem["mitigated_on"].fillna(0)
        sb = pivot_sem["baseline_control"].fillna(0)
        rel_var = (sm / m)**2 + (sb / b)**2
        pivot_mean["overhead_sem"] = (m / b) * np.sqrt(rel_var) * 100.0
        pivot_mean["overhead_sem"] = pivot_mean["overhead_sem"].fillna(0)
    else:
        pivot_mean["overhead_sem"] = 0.0
        
    return pivot_mean.reset_index()


def plot_figure1(df: pd.DataFrame, out_dir: Path):
    """Figure 1: Unified Multi-Syscall Amortization Curves (Warm Cache)."""
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5))
    
    xticks = [512, 1024, 4096, 16384, 65536, 262144, 1048576]
    xticklabels = [format_bytes(x) for x in xticks]
    
    # Left: Raw System-Call Latency (log scale)
    for syscall, color, marker, label in [
        ("write", "#1f77b4", "o", "write()"),
        ("read", "#2ca02c", "s", "read()"),
        ("ftruncate", "#ff7f0e", "^", "ftruncate()"),
    ]:
        sub_base = df[(df["syscall"] == syscall) & (df["cache_state"] == "warm") & 
                      (df["metric"] == "latency_ns") & (df["kernel_variant"] == "baseline_control")]
        sub_mit = df[(df["syscall"] == syscall) & (df["cache_state"] == "warm") & 
                     (df["metric"] == "latency_ns") & (df["kernel_variant"] == "mitigated_on")]
        
        if not sub_base.empty:
            p_base = sub_base.groupby("block_size_bytes")["value"].agg(["mean", "sem"]).reset_index()
            yerr_base = (p_base["sem"] / 1000.0) if (p_base["sem"].notna() & (p_base["sem"] > 0)).any() else None
            ax1.errorbar(p_base["block_size_bytes"], p_base["mean"] / 1000.0, yerr=yerr_base, capsize=3,
                         linestyle=":", color=color, marker=marker, alpha=0.7, label=f"{label} [Control]")
        if not sub_mit.empty:
            p_mit = sub_mit.groupby("block_size_bytes")["value"].agg(["mean", "sem"]).reset_index()
            yerr_mit = (p_mit["sem"] / 1000.0) if (p_mit["sem"].notna() & (p_mit["sem"] > 0)).any() else None
            ax1.errorbar(p_mit["block_size_bytes"], p_mit["mean"] / 1000.0, yerr=yerr_mit, capsize=3,
                         linestyle="-", color=color, marker=marker, label=f"{label} [Mitigated]")
    
    ax1.set_xscale("log", base=2)
    ax1.set_yscale("log")
    ax1.set_xlabel("Operation Size (Bytes)")
    ax1.set_ylabel("Mean Latency (µs, log scale)")
    ax1.set_title("(a) System-Call Latency Scaling")
    ax1.set_xticks(xticks)
    ax1.set_xticklabels(xticklabels)
    ax1.grid(True)
    ax1.legend(loc="upper left", frameon=True, fontsize=8)
    
    # Right: Relative Overhead (%)
    w_df = calculate_overhead(df, "write", "warm", "latency_ns")
    if w_df is not None and not w_df.empty:
        yerr_w = w_df["overhead_sem"] if ("overhead_sem" in w_df.columns and (w_df["overhead_sem"] > 0).any()) else None
        ax2.errorbar(w_df["block_size_bytes"], w_df["overhead_pct"], yerr=yerr_w, capsize=3,
                     marker="o", color="#1f77b4", label="write() [Scope Enter + Exit]")
    
    r_df = calculate_overhead(df, "read", "warm", "latency_ns")
    if r_df is not None and not r_df.empty:
        yerr_r = r_df["overhead_sem"] if ("overhead_sem" in r_df.columns and (r_df["overhead_sem"] > 0).any()) else None
        ax2.errorbar(r_df["block_size_bytes"], r_df["overhead_pct"], yerr=yerr_r, capsize=3,
                     marker="s", color="#2ca02c", linestyle="--", label="read() [Zero Toggles]")
    
    t_df = calculate_overhead(df, "ftruncate", "warm", "latency_ns")
    if t_df is not None and not t_df.empty:
        yerr_t = t_df["overhead_sem"] if ("overhead_sem" in t_df.columns and (t_df["overhead_sem"] > 0).any()) else None
        ax2.errorbar(t_df["block_size_bytes"], t_df["overhead_pct"], yerr=yerr_t, capsize=3,
                     marker="^", color="#ff7f0e", linestyle="-.", label="ftruncate() [Metadata Scope]")
    
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


def plot_figure2(df: pd.DataFrame, out_dir: Path):
    """Figure 2: Cold vs. Warm Cache Scaling (Allocator Overhead Isolation)."""
    w_sub = df[(df["syscall"] == "write") & (df["cache_state"] == "warm") & 
               (df["metric"] == "latency_ns") & (df["kernel_variant"] == "mitigated_on")]
    c_sub = df[(df["syscall"] == "write") & (df["cache_state"] == "cold") & 
               (df["metric"] == "latency_ns") & (df["kernel_variant"] == "mitigated_on")]
    
    if w_sub.empty or c_sub.empty:
        print("[WARN] Incomplete warm/cold write latency data for Figure 2. Skipping.")
        return
    
    w_agg = w_sub.groupby("block_size_bytes")["value"].agg(["mean", "sem"]).reset_index()
    c_agg = c_sub.groupby("block_size_bytes")["value"].agg(["mean", "sem"]).reset_index()
    
    merged = pd.merge(w_agg, c_agg, on="block_size_bytes", suffixes=("_warm", "_cold"))
    merged = merged.sort_values("block_size_bytes").reset_index(drop=True)
    merged["value_warm"] = merged["mean_warm"]
    merged["value_cold"] = merged["mean_cold"]
    merged["sem_warm"] = merged["sem_warm"].fillna(0)
    merged["sem_cold"] = merged["sem_cold"].fillna(0)
    merged["delta_alloc_ns"] = merged["value_cold"] - merged["value_warm"]
    merged["delta_alloc_us"] = merged["delta_alloc_ns"] / 1000.0
    merged["delta_alloc_sem_us"] = np.sqrt(merged["sem_cold"]**2 + merged["sem_warm"]**2) / 1000.0
    
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
    xticks = [512, 4096, 65536, 262144, 1048576]
    xticklabels = [format_bytes(x) for x in xticks]
    
    # Left: Warm vs Cold raw latencies
    yerr_warm = (merged["sem_warm"] / 1000.0) if (merged["sem_warm"] > 0).any() else None
    yerr_cold = (merged["sem_cold"] / 1000.0) if (merged["sem_cold"] > 0).any() else None
    ax1.errorbar(merged["block_size_bytes"], merged["value_warm"] / 1000.0, yerr=yerr_warm, capsize=3,
                 marker="o", color="#1f77b4", label="Warm Cache (Overwrite)")
    ax1.errorbar(merged["block_size_bytes"], merged["value_cold"] / 1000.0, yerr=yerr_cold, capsize=3,
                 marker="s", color="#d62728", label="Cold Cache (First-Touch Allocation)")
    ax1.set_xscale("log", base=2)
    ax1.set_xlabel("Operation Size (Bytes)")
    ax1.set_ylabel("Mean System-Call Latency (µs)")
    ax1.set_title("(a) Write Latency: Cold vs. Warm")
    ax1.grid(True)
    ax1.legend()
    ax1.set_xticks(xticks)
    ax1.set_xticklabels(xticklabels)
    
    # Right: Isolated Allocation Overhead (Delta)
    yerr_delta = merged["delta_alloc_sem_us"] if (merged["delta_alloc_sem_us"] > 0).any() else None
    ax2.errorbar(merged["block_size_bytes"], merged["delta_alloc_us"], yerr=yerr_delta, capsize=3,
                 marker="^", color="#9467bd", label="Allocation Delta (Cold - Warm)")
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


def plot_figure3(df: pd.DataFrame, out_dir: Path):
    """Figure 3: Kernel Ablation Comparison (Throughput & Latency)."""
    sub_tp = df[(df["syscall"] == "write") & (df["cache_state"] == "warm") & (df["metric"] == "throughput_mbs")]
    sub_lat = df[(df["syscall"] == "write") & (df["cache_state"] == "warm") & (df["metric"] == "latency_ns")]
    
    if sub_tp.empty:
        print("[WARN] Throughput metrics missing for Figure 3. Skipping.")
        return
    
    p_tp = sub_tp.pivot_table(index="block_size_bytes", columns="kernel_variant", values="value", aggfunc="mean").reset_index()
    p_tp_sem = sub_tp.pivot_table(index="block_size_bytes", columns="kernel_variant", values="value", aggfunc="sem").reset_index()
    
    p_lat = sub_lat.pivot_table(index="block_size_bytes", columns="kernel_variant", values="value", aggfunc="mean").reset_index() if not sub_lat.empty else pd.DataFrame()
    p_lat_sem = sub_lat.pivot_table(index="block_size_bytes", columns="kernel_variant", values="value", aggfunc="sem").reset_index() if not sub_lat.empty else pd.DataFrame()
    
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5))
    xticks = [512, 2048, 8192, 32768, 131072, 524288, 1048576]
    xticklabels = [format_bytes(x) for x in xticks]
    
    colors = {"baseline_control": "#7f7f7f", "mitigated_off": "#1f77b4", "mitigated_on": "#d62728"}
    labels = {
        "baseline_control": "Baseline Control (Vanilla 5.18)",
        "mitigated_off": "Mitigated Off (Ablation Control)",
        "mitigated_on": "Mitigated On (Active PKS)"
    }
    
    # Left: Throughput
    for col in ["baseline_control", "mitigated_off", "mitigated_on"]:
        if col in p_tp.columns:
            yerr = p_tp_sem[col].fillna(0) if (col in p_tp_sem.columns and (p_tp_sem[col] > 0).any()) else None
            ax1.errorbar(p_tp["block_size_bytes"], p_tp[col], yerr=yerr, capsize=3,
                         marker="o", color=colors.get(col, "#000"), label=labels.get(col, col))
    
    ax1.set_xscale("log", base=2)
    ax1.set_xlabel("Block Size (Bytes)")
    ax1.set_ylabel("Sequential Write Throughput (MB/s)")
    ax1.set_title("(a) Write Throughput")
    ax1.set_xticks(xticks)
    ax1.set_xticklabels(xticklabels)
    ax1.grid(True)
    ax1.legend()
    
    # Right: Latency
    if not p_lat.empty:
        for col in ["baseline_control", "mitigated_off", "mitigated_on"]:
            if col in p_lat.columns:
                yerr = (p_lat_sem[col] / 1000.0).fillna(0) if (col in p_lat_sem.columns and (p_lat_sem[col] > 0).any()) else None
                ax2.errorbar(p_lat["block_size_bytes"], p_lat[col] / 1000.0, yerr=yerr, capsize=3,
                             marker="s", color=colors.get(col, "#000"), label=labels.get(col, col))
        ax2.set_xscale("log", base=2)
        ax2.set_yscale("log")
        ax2.set_xlabel("Block Size (Bytes)")
        ax2.set_ylabel("Mean Latency (µs, log scale)")
        ax2.set_title("(b) Write Latency")
        ax2.set_xticks(xticks)
        ax2.set_xticklabels(xticklabels)
        ax2.grid(True)
        ax2.legend()
    
    fig.suptitle("Figure 3: Kernel Performance Comparison & Ablation", y=1.01)
    plt.tight_layout()
    fig.savefig(out_dir / "figure3_kernel_ablation.pdf", bbox_inches="tight")
    fig.savefig(out_dir / "figure3_kernel_ablation.png", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"[INFO] Generated Figure 3 -> {out_dir}/figure3_kernel_ablation.pdf")


def plot_figure4(df: pd.DataFrame, out_dir: Path):
    """Figure 4: Multi-Core Concurrency Scaling (Aggregate Throughput & Latency)."""
    sub_tp = df[(df["workload"] == "concurrency") & (df["metric"] == "throughput_mbs")]
    sub_lat = df[(df["workload"] == "concurrency") & (df["metric"] == "latency_ns")]
    
    if sub_tp.empty:
        print("[WARN] Concurrency metrics missing for Figure 4. Skipping.")
        return
    
    p_tp = sub_tp.pivot_table(index="num_jobs", columns="kernel_variant", values="value", aggfunc="mean").reset_index()
    p_tp_sem = sub_tp.pivot_table(index="num_jobs", columns="kernel_variant", values="value", aggfunc="sem").reset_index()
    
    p_lat = sub_lat.pivot_table(index="num_jobs", columns="kernel_variant", values="value", aggfunc="mean").reset_index() if not sub_lat.empty else pd.DataFrame()
    p_lat_sem = sub_lat.pivot_table(index="num_jobs", columns="kernel_variant", values="value", aggfunc="sem").reset_index() if not sub_lat.empty else pd.DataFrame()
    
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
    jobs = sorted(p_tp["num_jobs"].unique())
    
    colors = {"baseline_control": "#7f7f7f", "mitigated_off": "#1f77b4", "mitigated_on": "#d62728"}
    labels = {
        "baseline_control": "Baseline Control",
        "mitigated_off": "Mitigated Off",
        "mitigated_on": "Mitigated On"
    }
    
    # Left: Aggregate Throughput
    for col in ["baseline_control", "mitigated_off", "mitigated_on"]:
        if col in p_tp.columns:
            yerr = p_tp_sem[col].fillna(0) if (col in p_tp_sem.columns and (p_tp_sem[col] > 0).any()) else None
            ax1.errorbar(p_tp["num_jobs"], p_tp[col], yerr=yerr, capsize=3,
                         marker="o", linewidth=2.2, color=colors.get(col, "#000"), label=labels.get(col, col))
    
    ax1.set_xlabel("Concurrent Worker Threads (numjobs)")
    ax1.set_ylabel("Aggregate Throughput (MB/s)")
    ax1.set_title("(a) Multi-Threaded Write Throughput")
    ax1.set_xticks(jobs)
    ax1.grid(True)
    ax1.legend()
    
    # Right: Per-Thread Average Latency
    if not p_lat.empty:
        for col in ["baseline_control", "mitigated_off", "mitigated_on"]:
            if col in p_lat.columns:
                yerr = (p_lat_sem[col] / 1000.0).fillna(0) if (col in p_lat_sem.columns and (p_lat_sem[col] > 0).any()) else None
                ax2.errorbar(p_lat["num_jobs"], p_lat[col] / 1000.0, yerr=yerr, capsize=3,
                             marker="s", linewidth=2.2, color=colors.get(col, "#000"), label=labels.get(col, col))
        ax2.set_xlabel("Concurrent Worker Threads (numjobs)")
        ax2.set_ylabel("Average Request Latency (µs)")
        ax2.set_title("(b) Per-Thread Request Latency")
        ax2.set_xticks(jobs)
        ax2.grid(True)
        ax2.legend()
    
    fig.suptitle("Figure 4: Multi-Core Concurrency Scaling", y=1.01)
    plt.tight_layout()
    fig.savefig(out_dir / "figure4_concurrency_scaling.pdf", bbox_inches="tight")
    fig.savefig(out_dir / "figure4_concurrency_scaling.png", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"[INFO] Generated Figure 4 -> {out_dir}/figure4_concurrency_scaling.pdf")


def plot_figure5(df: pd.DataFrame, out_dir: Path):
    """Figure 5: SQLite Macrobenchmark Throughput & Latency."""
    sub = df[(df["workload"] == "sqlite_macro") & (df["metric"] == "tps")]
    
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.5))
    if sub.empty:
        ax1.text(0.5, 0.5, "SQLite Macrobenchmark Not Executed", ha="center", va="center")
        ax1.set_axis_off()
        ax2.set_axis_off()
    else:
        pivot_mean = sub.pivot_table(index="cache_state", columns="kernel_variant", values="value", aggfunc="mean")
        pivot_sem = sub.pivot_table(index="cache_state", columns="kernel_variant", values="value", aggfunc="sem")
        variants = [v for v in ["baseline_control", "mitigated_off", "mitigated_on"] if v in pivot_mean.columns]
        colors = {"baseline_control": "#7f7f7f", "mitigated_off": "#1f77b4", "mitigated_on": "#d62728"}
        labels = {"baseline_control": "Baseline Control", "mitigated_off": "Mitigated Off (Ablation)", "mitigated_on": "Mitigated On (PKS)"}
        
        # Panel (a): synchronous=FULL
        if "sync_full" in pivot_mean.index:
            vals_full = [pivot_mean.loc["sync_full", v] for v in variants]
            yerr_full = [pivot_sem.loc["sync_full", v] if (v in pivot_sem.columns and pd.notna(pivot_sem.loc["sync_full", v])) else 0.0 for v in variants]
            has_err_full = any(e > 0 for e in yerr_full)
            bars1 = ax1.bar(variants, vals_full, yerr=yerr_full if has_err_full else None, capsize=3,
                            color=[colors[v] for v in variants], width=0.55)
            ax1.set_title("(a) synchronous=FULL (fsync bounded)")
            ax1.set_ylabel("Transactions Per Second (TPS)")
            ax1.set_xticks(range(len(variants)))
            ax1.set_xticklabels([labels[v] for v in variants], rotation=15, ha="right")
            ax1.grid(axis="y")
            for idx, bar in enumerate(bars1):
                y = bar.get_height()
                err = yerr_full[idx] if has_err_full else 0.0
                ax1.annotate(f"{y:.2f}", xy=(bar.get_x() + bar.get_width()/2, y + err),
                             xytext=(0, 3), textcoords="offset points", ha="center", va="bottom", fontsize=8.5)
        
        # Panel (b): synchronous=OFF
        if "sync_off" in pivot_mean.index:
            vals_off = [pivot_mean.loc["sync_off", v] for v in variants]
            yerr_off = [pivot_sem.loc["sync_off", v] if (v in pivot_sem.columns and pd.notna(pivot_sem.loc["sync_off", v])) else 0.0 for v in variants]
            has_err_off = any(e > 0 for e in yerr_off)
            bars2 = ax2.bar(variants, vals_off, yerr=yerr_off if has_err_off else None, capsize=3,
                            color=[colors[v] for v in variants], width=0.55)
            ax2.set_title("(b) synchronous=OFF (Memory Page Cache)")
            ax2.set_ylabel("Transactions Per Second (TPS)")
            ax2.set_xticks(range(len(variants)))
            ax2.set_xticklabels([labels[v] for v in variants], rotation=15, ha="right")
            ax2.grid(axis="y")
            for idx, bar in enumerate(bars2):
                y = bar.get_height()
                err = yerr_off[idx] if has_err_off else 0.0
                ax2.annotate(f"{y:.1f}", xy=(bar.get_x() + bar.get_width()/2, y + err),
                             xytext=(0, 3), textcoords="offset points", ha="center", va="bottom", fontsize=8.5)
        
        fig.suptitle("Figure 5: SQLite Macrobenchmark (Rollback Journal Mode)", y=1.01)
    
    plt.tight_layout()
    fig.savefig(out_dir / "figure5_sqlite_macro.pdf", bbox_inches="tight")
    fig.savefig(out_dir / "figure5_sqlite_macro.png", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"[INFO] Generated Figure 5 -> {out_dir}/figure5_sqlite_macro.pdf")


def generate_table1_tost(df: pd.DataFrame, out_dir: Path):
    """Table 1: Statistical Equivalence (TOST) Summary for Read Parity."""
    read_sub = df[(df["syscall"] == "read") & (df["cache_state"] == "warm") & (df["metric"] == "latency_ns")]
    
    tex_path = out_dir / "table1_tost.tex"
    md_path = out_dir / "table1_tost.md"
    
    rows = []
    margin_pct = 2.0  # Practical equivalence bound: +/- 2%
    is_distribution = False
    
    if not read_sub.empty:
        # Check sample counts per group
        sample_counts = read_sub.groupby(["block_size_bytes", "kernel_variant"])["value"].count()
        is_distribution = (sample_counts > 1).any()
        
        piv_mean = read_sub.pivot_table(index="block_size_bytes", columns="kernel_variant", values="value", aggfunc="mean").reset_index()
        piv_std = read_sub.pivot_table(index="block_size_bytes", columns="kernel_variant", values="value", aggfunc="std").reset_index() if is_distribution else None
        
        if "baseline_control" in piv_mean.columns and "mitigated_on" in piv_mean.columns:
            for _, row in piv_mean.iterrows():
                bs = row["block_size_bytes"]
                base_mean = row["baseline_control"]
                mit_mean = row["mitigated_on"]
                diff_pct = ((mit_mean - base_mean) / base_mean) * 100.0
                
                if is_distribution and piv_std is not None:
                    # Multi-sample TOST calculation using Welch-Satterthwaite degrees of freedom
                    b_vals = read_sub[(read_sub["block_size_bytes"] == bs) & (read_sub["kernel_variant"] == "baseline_control")]["value"].values
                    m_vals = read_sub[(read_sub["block_size_bytes"] == bs) & (read_sub["kernel_variant"] == "mitigated_on")]["value"].values
                    n_b, n_m = len(b_vals), len(m_vals)
                    delta = (margin_pct / 100.0) * base_mean
                    
                    if n_b >= 2 and n_m >= 2:
                        v_b = np.var(b_vals, ddof=1) / n_b
                        v_m = np.var(m_vals, ddof=1) / n_m
                        se = math.sqrt(v_b + v_m)
                        diff = mit_mean - base_mean
                        t1 = (diff - (-delta)) / se if se > 0 else 0
                        t2 = (diff - delta) / se if se > 0 else 0
                        denom = (v_b**2 / (n_b - 1)) + (v_m**2 / (n_m - 1)) if (n_b > 1 and n_m > 1) else 0
                        df_val = ((v_b + v_m)**2 / denom) if denom > 0 else (n_b + n_m - 2)
                        p1 = 1 - stats.t.cdf(t1, df_val)
                        p2 = stats.t.cdf(t2, df_val)
                        p_tost = max(p1, p2)
                        equiv = f"Yes (p={p_tost:.3f})" if p_tost < 0.05 else f"No (p={p_tost:.3f})"
                    else:
                        equiv = "Yes (Point Est)" if abs(diff_pct) <= margin_pct else "No (Point Est)"
                else:
                    equiv = "Within Bound" if abs(diff_pct) <= margin_pct else "Outside Bound"
                
                rows.append((format_bytes(bs), f"{base_mean:.1f}", f"{mit_mean:.1f}", f"{diff_pct:+.2f}%", f"±{margin_pct:.1f}%", equiv))
    
    # Write Markdown version
    with open(md_path, "w", encoding="utf-8") as f:
        f.write("# Table 1: Two One-Sided Tests (TOST) Read-Path Parity\n\n")
        f.write("| Block Size | Baseline Mean (ns) | Mitigated Mean (ns) | Difference (%) | Equivalence Bound | Equivalent? |\n")
        f.write("|:---|:---|:---|:---|:---|:---|\n")
        for r in rows:
            f.write(f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} | **{r[5]}** |\n")
        
        if not is_distribution:
            f.write("\n*Note on Methodology: The above table reflects single-run point estimates. Formal hypothesis rejection (H01/H02 with α=0.05) requires evaluating N >= 30 independent runs to compute Welch's degrees of freedom and two one-sided t-statistics against the ±2.0% equivalence margin. Under QEMU TCG software emulation, translated MSR helper overhead inflates small-block measurements.*\n")
        else:
            f.write("\n*Note: Evaluated with Two One-Sided Tests (TOST) at 95% confidence level (α=0.05) across sample runs.*\n")
    
    # Write LaTeX version
    with open(tex_path, "w", encoding="utf-8") as f:
        f.write("\\begin{table}[htbp]\n")
        f.write("\\centering\n")
        f.write("\\caption{Two One-Sided Tests (TOST) Statistical Equivalence for Read-Path Parity}\n")
        f.write("\\label{tab:read_tost}\n")
        f.write("\\begin{tabular}{lrrrrr}\n")
        f.write("\\toprule\n")
        f.write("Block Size & Baseline (ns) & Mitigated (ns) & Difference (\\%) & Bound & Equivalent? \\\\\n")
        f.write("\\midrule\n")
        for r in rows:
            f.write(f"{r[0]} & {r[1]} & {r[2]} & {r[3]} & {r[4]} & {r[5]} \\\\\n")
        f.write("\\bottomrule\n")
        f.write("\\end{tabular}\n")
        f.write("\\end{table}\n")
    
    print(f"[INFO] Generated Table 1 -> {md_path} and {tex_path}")


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    env_dir = script_dir.parent.parent
    
    csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else env_dir / "results" / "processed" / "benchmark_summary.csv"
    out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else env_dir / "results" / "processed" / "figures"
    out_dir.mkdir(parents=True, exist_ok=True)
    
    if not csv_path.exists():
        print(f"[WARN] Benchmark summary CSV not found at {csv_path}. Skipping plot generation.")
        return 0
    
    try:
        df = pd.read_csv(csv_path)
    except Exception as e:
        print(f"[ERROR] Failed to read {csv_path}: {e}", file=sys.stderr)
        return 1
    
    if df.empty:
        print("[WARN] Benchmark summary CSV is empty. Skipping plot generation.")
        return 0
    
    plot_figure1(df, out_dir)
    plot_figure2(df, out_dir)
    plot_figure3(df, out_dir)
    plot_figure4(df, out_dir)
    plot_figure5(df, out_dir)
    generate_table1_tost(df, out_dir)
    
    print("[INFO] All thesis figures and tables generated successfully!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
