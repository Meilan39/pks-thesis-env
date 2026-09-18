#!/usr/bin/env python3
"""
scripts/parse_results.py - Normalize raw benchmark outputs into canonical dataset.

Parses raw JSON artifacts from fio, truncate_bench, and sqlite_bench across
baseline_control, mitigated_off, and mitigated_on.

Emits:
  - results/processed/benchmark_summary.csv (canonical tidy long-format schema)
  - results/processed/run_metadata.json
"""

import csv
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional


def parse_fio_json(file_path: Path, kernel_variant: str, run_id: str) -> List[Dict[str, Any]]:
    rows = []
    fname = file_path.name
    
    # Identify test type from filename
    # Pattern: fio_<write|read|truncate>_<warm|cold>_<bs>.json or fio_concurrency_jobs_<jobs>.json
    m_sweep = re.match(r"fio_(write|read|truncate)_(warm|cold)_(\d+)\.json", fname)
    m_concur = re.match(r"fio_concurrency_jobs_(\d+)\.json", fname)
    
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"[WARN] Failed to parse {file_path}: {e}", file=sys.stderr)
        return []
    
    jobs = data.get("jobs", [])
    if not jobs:
        return []
    job = jobs[0]
    
    if m_sweep:
        op = m_sweep.group(1)
        syscall = "ftruncate" if op == "truncate" else op
        fio_dir = "write" if op == "truncate" else op
        cache_state = m_sweep.group(2)
        bs_bytes = int(m_sweep.group(3))
        workload = "sweep"
        num_jobs = 1
    elif m_concur:
        syscall = "write"
        fio_dir = "write"
        cache_state = "warm"
        bs_bytes = 4096
        workload = "concurrency"
        num_jobs = int(m_concur.group(1))
    else:
        return []
    
    io_data = job.get(fio_dir, {})
    if not io_data:
        return []
    
    # Extract throughput (MB/s)
    bw_bytes = io_data.get("bw_bytes", 0)
    if bw_bytes:
        bw_mbs = float(bw_bytes) / (1024.0 * 1024.0)
    else:
        bw_kb = io_data.get("bw", 0)
        bw_mbs = float(bw_kb) / 1024.0
    
    # Extract latency (ns)
    lat_ns_data = io_data.get("lat_ns", {})
    if lat_ns_data and "mean" in lat_ns_data:
        lat_ns = float(lat_ns_data["mean"])
    else:
        clat_ns_data = io_data.get("clat_ns", {})
        if clat_ns_data and "mean" in clat_ns_data:
            lat_ns = float(clat_ns_data["mean"])
        else:
            # Fallback to lat (microseconds)
            lat_data = io_data.get("lat", {})
            lat_ns = float(lat_data.get("mean", 0)) * 1000.0
    
    iops = float(io_data.get("iops", 0))
    
    rows.append({
        "workload": workload,
        "syscall": syscall,
        "block_size_bytes": bs_bytes,
        "cache_state": cache_state,
        "num_jobs": num_jobs,
        "kernel_variant": kernel_variant,
        "metric": "throughput_mbs",
        "value": round(bw_mbs, 4),
        "unit": "MB/s",
        "run_id": run_id
    })
    
    rows.append({
        "workload": workload,
        "syscall": syscall,
        "block_size_bytes": bs_bytes,
        "cache_state": cache_state,
        "num_jobs": num_jobs,
        "kernel_variant": kernel_variant,
        "metric": "latency_ns",
        "value": round(lat_ns, 2),
        "unit": "ns",
        "run_id": run_id
    })
    
    if iops > 0:
        rows.append({
            "workload": workload,
            "syscall": syscall,
            "block_size_bytes": bs_bytes,
            "cache_state": cache_state,
            "num_jobs": num_jobs,
            "kernel_variant": kernel_variant,
            "metric": "iops",
            "value": round(iops, 2),
            "unit": "iops",
            "run_id": run_id
        })
    
    return rows


def parse_truncate_json(file_path: Path, kernel_variant: str, run_id: str) -> List[Dict[str, Any]]:
    rows = []
    fname = file_path.name
    # Pattern: truncate_<warm|cold>_<bs>.json
    m = re.match(r"truncate_(warm|cold)_(\d+)\.json", fname)
    if not m:
        return []
    
    cache_state = m.group(1)
    bs_bytes = int(m.group(2))
    
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"[WARN] Failed to parse {file_path}: {e}", file=sys.stderr)
        return []
    
    lat_ns = float(data.get("latency_ns", 0))
    
    rows.append({
        "workload": "sweep",
        "syscall": "ftruncate",
        "block_size_bytes": bs_bytes,
        "cache_state": cache_state,
        "num_jobs": 1,
        "kernel_variant": kernel_variant,
        "metric": "latency_ns",
        "value": round(lat_ns, 2),
        "unit": "ns",
        "run_id": run_id
    })
    return rows


def parse_sqlite_json(file_path: Path, kernel_variant: str, run_id: str) -> List[Dict[str, Any]]:
    rows = []
    fname = file_path.name
    # Pattern: sqlite_<FULL|OFF>.json
    m = re.match(r"sqlite_(FULL|OFF)\.json", fname)
    if not m:
        return []
    
    sync_mode = m.group(1)
    
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"[WARN] Failed to parse {file_path}: {e}", file=sys.stderr)
        return []
    
    tps = float(data.get("tps", 0))
    lat_ns = float(data.get("latency_ns", 0))
    cache_state = f"sync_{sync_mode.lower()}"
    
    # Note: block_size_bytes is left empty per schema specification
    rows.append({
        "workload": "sqlite_macro",
        "syscall": "transaction",
        "block_size_bytes": "",
        "cache_state": cache_state,
        "num_jobs": 1,
        "kernel_variant": kernel_variant,
        "metric": "tps",
        "value": round(tps, 2),
        "unit": "tps",
        "run_id": run_id
    })
    
    rows.append({
        "workload": "sqlite_macro",
        "syscall": "transaction",
        "block_size_bytes": "",
        "cache_state": cache_state,
        "num_jobs": 1,
        "kernel_variant": kernel_variant,
        "metric": "latency_ns",
        "value": round(lat_ns, 2),
        "unit": "ns",
        "run_id": run_id
    })
    return rows


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    env_dir = script_dir.parent
    
    raw_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else env_dir / "results" / "raw"
    out_csv = Path(sys.argv[2]) if len(sys.argv) > 2 else env_dir / "results" / "processed" / "benchmark_summary.csv"
    out_meta = Path(sys.argv[3]) if len(sys.argv) > 3 else env_dir / "results" / "processed" / "run_metadata.json"
    
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    out_meta.parent.mkdir(parents=True, exist_ok=True)
    
    if not raw_dir.exists():
        # Fallback check inside results/extracted/bench
        alt_raw = env_dir / "results" / "extracted" / "bench"
        if alt_raw.exists():
            raw_dir = alt_raw
        else:
            print(f"[WARN] Raw directory does not exist: {raw_dir}. Generating empty summary template.")
            with open(out_csv, "w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                writer.writerow([
                    "workload", "syscall", "block_size_bytes", "cache_state",
                    "num_jobs", "kernel_variant", "metric", "value", "unit", "run_id"
                ])
            return 0
    
    all_rows: List[Dict[str, Any]] = []
    combined_meta: Dict[str, Any] = {}
    
    # Discover variants (directories or flat)
    subdirs = [d for d in raw_dir.iterdir() if d.is_dir()]
    variants_to_scan = []
    if subdirs:
        for d in subdirs:
            variants_to_scan.append((d.name, d))
    else:
        variants_to_scan.append(("default", raw_dir))
    
    run_counter = 1
    for variant, vdir in variants_to_scan:
        run_id = f"run_{run_counter:02d}"
        run_counter += 1
        
        # Look for run_metadata.json
        meta_file = vdir / "run_metadata.json"
        if meta_file.exists():
            try:
                with open(meta_file, "r", encoding="utf-8") as mf:
                    combined_meta[variant] = json.load(mf)
            except Exception:
                pass
        
        for json_file in sorted(vdir.glob("*.json")):
            if json_file.name == "run_metadata.json":
                continue
            
            if json_file.name.startswith("fio_"):
                rows = parse_fio_json(json_file, variant, run_id)
                all_rows.extend(rows)
            elif json_file.name.startswith("truncate_"):
                rows = parse_truncate_json(json_file, variant, run_id)
                all_rows.extend(rows)
            elif json_file.name.startswith("sqlite_"):
                rows = parse_sqlite_json(json_file, variant, run_id)
                all_rows.extend(rows)
    
    fieldnames = [
        "workload", "syscall", "block_size_bytes", "cache_state",
        "num_jobs", "kernel_variant", "metric", "value", "unit", "run_id"
    ]
    
    with open(out_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in all_rows:
            writer.writerow(r)
    
    with open(out_meta, "w", encoding="utf-8") as f:
        json.dump(combined_meta, f, indent=2)
    
    print(f"[INFO] Successfully parsed {len(all_rows)} benchmark rows -> {out_csv}")
    print(f"[INFO] Metadata saved -> {out_meta}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
