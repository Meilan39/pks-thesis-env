#!/usr/bin/env python3
"""
analyze_bench.py - Compare and format PKS buffered I/O benchmark results

Parses fio JSON output for control and mitigated runs, computes mean throughput,
IOPS, and latency across iterations, and formats a comparison table with overhead.
"""

import argparse
import json
import sys
from pathlib import Path
from statistics import mean, stdev


def parse_fio_json(file_path: Path) -> dict:
    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    job = data["jobs"][0]
    # Check if write or read workload
    write_bytes = job["write"]["io_bytes"]
    read_bytes = job["read"]["io_bytes"]

    if write_bytes >= read_bytes:
        stats = job["write"]
    else:
        stats = job["read"]

    bw_mb = stats["bw"] / 1024.0  # KiB/s to MiB/s
    iops = stats["iops"]
    lat_ms = stats["lat_ns"]["mean"] / 1_000_000.0  # ns to ms

    return {
        "bw_mb": bw_mb,
        "iops": iops,
        "lat_ms": lat_ms,
    }


def aggregate_workload(bench_dir: Path, workload_prefix: str) -> dict:
    files = sorted(bench_dir.glob(f"{workload_prefix}_run*.json"))
    if not files:
        # Check without run suffix
        files = sorted(bench_dir.glob(f"{workload_prefix}*.json"))

    if not files:
        return {}

    bws, iops_list, lats = [], [], []
    for fp in files:
        try:
            res = parse_fio_json(fp)
            bws.append(res["bw_mb"])
            iops_list.append(res["iops"])
            lats.append(res["lat_ms"])
        except Exception as e:
            print(f"Warning: Failed to parse {fp}: {e}", file=sys.stderr)

    if not bws:
        return {}

    return {
        "runs": len(bws),
        "bw_mean": mean(bws),
        "bw_std": stdev(bws) if len(bws) > 1 else 0.0,
        "iops_mean": mean(iops_list),
        "lat_mean": mean(lats),
    }


def main():
    parser = argparse.ArgumentParser(description="Analyze PKS evaluation fio benchmarks")
    parser.add_argument("--control-dir", type=Path, help="Directory containing control benchmark JSONs")
    parser.add_argument("--mitigated-dir", type=Path, help="Directory containing mitigated benchmark JSONs")
    parser.add_argument("--results-dir", type=Path, default=Path("results/extracted/bench"),
                        help="Unified directory containing benchmark JSONs")
    parser.add_argument("--markdown", action="store_true", default=True, help="Print formatted Markdown table")
    args = parser.parse_args()

    workloads = [
        ("write_4k", "Sync Write 4KB"),
        ("write_16k", "Sync Write 16KB"),
        ("write_64k", "Sync Write 64KB"),
        ("write_256k", "Sync Write 256KB"),
        ("write_1024k", "Sync Write 1MB"),
        ("read_4k", "Random Read 4KB"),
    ]

    ctrl_dir = args.control_dir or (args.results_dir / "control")
    mit_dir = args.mitigated_dir or (args.results_dir / "mitigated")

    # If subdirectories don't exist, try scanning results_dir directly
    if not ctrl_dir.exists() and not mit_dir.exists() and args.results_dir.exists():
        print(f"=== Single Directory Benchmark Summary: {args.results_dir} ===\n")
        print("| Workload | Runs | Throughput (MB/s) | IOPS | Mean Latency (ms) |")
        print("| :--- | :---: | :---: | :---: | :---: |")
        for key, name in workloads:
            data = aggregate_workload(args.results_dir, key)
            if data:
                print(f"| {name} | {data['runs']} | {data['bw_mean']:.2f} ± {data['bw_std']:.2f} | "
                      f"{data['iops_mean']:.0f} | {data['lat_mean']:.3f} |")
            else:
                print(f"| {name} | 0 | N/A | N/A | N/A |")
        return

    print("### Micro-benchmark Performance Comparison (Control vs. Mitigated)\n")
    print("| Workload | Control (MB/s) | Mitigated (MB/s) | Throughput Overhead | Mitigated Latency |")
    print("| :--- | :---: | :---: | :---: | :---: |")

    for key, name in workloads:
        ctrl_data = aggregate_workload(ctrl_dir, key) if ctrl_dir.exists() else {}
        mit_data = aggregate_workload(mit_dir, key) if mit_dir.exists() else {}

        ctrl_bw_str = f"{ctrl_data['bw_mean']:.2f}" if ctrl_data else "N/A"
        mit_bw_str = f"{mit_data['bw_mean']:.2f}" if mit_data else "N/A"
        lat_str = f"{mit_data['lat_mean']:.3f} ms" if mit_data else "N/A"

        if ctrl_data and mit_data and ctrl_data["bw_mean"] > 0:
            overhead = ((ctrl_data["bw_mean"] - mit_data["bw_mean"]) / ctrl_data["bw_mean"]) * 100.0
            overhead_str = f"{overhead:+.2f}%"
        else:
            overhead_str = "N/A"

        print(f"| {name} | {ctrl_bw_str} | {mit_bw_str} | {overhead_str} | {lat_str} |")

    print("\n*Throughput Overhead calculated as `(Control - Mitigated) / Control * 100`.*")


if __name__ == "__main__":
    main()
