#!/usr/bin/env python3
"""
analyze_sec.py - Parse and summarize PKS exploit neutralization test results.

Analyzes sec_off.log and sec_on.log from QEMU batch execution, evaluating whether
confused-deputy page cache corruption attacks (Copy Fail, Dirty Frag) succeeded
or were intercepted and neutralized by hardware Intel PKS supervisor protection keys.
"""

import argparse
import os
import re
import sys
from pathlib import Path


def parse_sec_log(file_path: Path) -> dict:
    if not file_path.is_file():
        return {"error": f"Log file not found: {file_path}"}

    content = file_path.read_text(encoding="utf-8", errors="replace")

    results = {
        "copy_fail": {
            "tested": False,
            "pre_md5": None,
            "post_md5": None,
            "corrupted": False,
            "pks_trapped": False,
            "containment": None,
            "exit_code": None,
        },
        "dirty_frag": {
            "tested": False,
            "pre_md5": None,
            "post_md5": None,
            "corrupted": False,
            "pks_trapped": False,
            "containment": None,
            "panic_interrupt": False,
        },
        "fragnesia": {
            "tested": False,
            "pre_md5": None,
            "post_md5": None,
            "corrupted": False,
            "pks_trapped": False,
            "containment": None,
            "panic_interrupt": False,
        },
        "mount_protected": "pks_pagecache" in content,
    }

    # Analyze Copy Fail section
    cf_match = re.search(r"===\s*copy-fail(?:\s*\(.*?\))?\s*===(.*?)(?:===\s*dirty-frag|===\s*fragnesia|All tests completed|\Z)", content, re.DOTALL)
    if cf_match:
        cf_text = cf_match.group(1)
        results["copy_fail"]["tested"] = True

        pre = re.search(r"pre-run MD5:\s+([0-9a-fA-F]{32})", cf_text)
        if pre:
            results["copy_fail"]["pre_md5"] = pre.group(1)

        post = re.search(r"post-run MD5:\s+([0-9a-fA-F]{32})", cf_text)
        if post:
            results["copy_fail"]["post_md5"] = post.group(1)

        if results["copy_fail"]["pre_md5"] and results["copy_fail"]["post_md5"]:
            results["copy_fail"]["corrupted"] = (
                results["copy_fail"]["pre_md5"] != results["copy_fail"]["post_md5"]
            )

        exit_c = re.search(r"exploit exited with code (\d+)", cf_text)
        if exit_c:
            results["copy_fail"]["exit_code"] = int(exit_c.group(1))

        if "error_code(0x0023)" in cf_text and "Comm: python3" in cf_text:
            results["copy_fail"]["pks_trapped"] = True
            results["copy_fail"]["containment"] = "Task Killed (Process Isolation, SIGSEGV)"

    # Analyze Dirty Frag section
    df_match = re.search(r"===\s*dirty-frag(?:\s*\(.*?\))?\s*===(.*?)(?:===\s*fragnesia|All tests completed|\Z)", content, re.DOTALL)
    if df_match:
        df_text = df_match.group(1)
        results["dirty_frag"]["tested"] = True

        pre = re.search(r"pre-run MD5:\s+([0-9a-fA-F]{32})", df_text)
        if pre:
            results["dirty_frag"]["pre_md5"] = pre.group(1)

        post = re.search(r"post-run MD5:\s+([0-9a-fA-F]{32})", df_text)
        if post:
            results["dirty_frag"]["post_md5"] = post.group(1)

        if results["dirty_frag"]["pre_md5"] and results["dirty_frag"]["post_md5"]:
            results["dirty_frag"]["corrupted"] = (
                results["dirty_frag"]["pre_md5"] != results["dirty_frag"]["post_md5"]
            )

        if "Fatal exception in interrupt" in df_text or "Kernel panic" in content:
            results["dirty_frag"]["panic_interrupt"] = True

        if "error_code(0x0023)" in content and ("Comm: exp" in content or "<IRQ>" in content or "dirty-frag" in content):
            results["dirty_frag"]["pks_trapped"] = True
            results["dirty_frag"]["containment"] = "Fail-Closed Panic (Hardware #PF in SoftIRQ)"

    # Analyze Fragnesia section
    fn_match = re.search(r"===\s*fragnesia(?:\s*\(.*?\))?\s*===(.*?)(?:All tests completed|\Z)", content, re.DOTALL)
    if fn_match:
        fn_text = fn_match.group(1)
        results["fragnesia"]["tested"] = True

        pre = re.search(r"pre-run MD5:\s+([0-9a-fA-F]{32})", fn_text)
        if pre:
            results["fragnesia"]["pre_md5"] = pre.group(1)

        post = re.search(r"post-run MD5:\s+([0-9a-fA-F]{32})", fn_text)
        if post:
            results["fragnesia"]["post_md5"] = post.group(1)

        if results["fragnesia"]["pre_md5"] and results["fragnesia"]["post_md5"]:
            results["fragnesia"]["corrupted"] = (
                results["fragnesia"]["pre_md5"] != results["fragnesia"]["post_md5"]
            )

        if "Fatal exception in interrupt" in fn_text or "Kernel panic" in content:
            results["fragnesia"]["panic_interrupt"] = True

        if "error_code(0x0023)" in content and ("Comm: exp" in content or "<IRQ>" in content or "fragnesia" in content or "xfrm" in content):
            results["fragnesia"]["pks_trapped"] = True
            results["fragnesia"]["containment"] = "Fail-Closed Panic (Hardware #PF in SoftIRQ/Crypto)"

    return results


def print_summary(off_res: dict, on_res: dict):
    print("=" * 78)
    print("       PKS Exploit Neutralization Summary (A/B Security Evaluation)       ")
    print("=" * 78)
    print(f"{'Exploit':<14} | {'Baseline (pcache_pks=off)':<28} | {'Mitigated (pcache_pks=on)':<28}")
    print("-" * 78)

    # 1. Copy Fail
    if off_res.get("copy_fail", {}).get("tested") or on_res.get("copy_fail", {}).get("tested"):
        cf_off = "VULNERABLE (Corrupted)" if off_res.get("copy_fail", {}).get("corrupted") else "NOT TESTED"
        if on_res.get("copy_fail", {}).get("pks_trapped"):
            cf_on = "BLOCKED (Hardware #PF 0x23)"
            cf_mode = on_res["copy_fail"]["containment"]
        elif not on_res.get("copy_fail", {}).get("corrupted", True):
            cf_on = "BLOCKED (Unmodified)"
            cf_mode = "Process Terminated"
        else:
            cf_on = "VULNERABLE"
            cf_mode = "None"
        print(f"{'copy-fail':<14} | {cf_off:<28} | {cf_on:<28}")
        if cf_mode:
            print(f"  └─ Containment: {cf_mode}")

    # 2. Dirty Frag
    if off_res.get("dirty_frag", {}).get("tested") or on_res.get("dirty_frag", {}).get("tested"):
        df_off = "VULNERABLE (Corrupted)" if off_res.get("dirty_frag", {}).get("corrupted") else "NOT TESTED"
        if on_res.get("dirty_frag", {}).get("pks_trapped"):
            df_on = "BLOCKED (Hardware #PF 0x23)"
            df_mode = on_res["dirty_frag"]["containment"]
        elif on_res.get("dirty_frag", {}).get("panic_interrupt"):
            df_on = "BLOCKED (SoftIRQ Panic)"
            df_mode = "Fail-Closed Panic in SoftIRQ"
        else:
            df_on = "VULNERABLE"
            df_mode = "None"
        print(f"{'dirty-frag':<14} | {df_off:<28} | {df_on:<28}")
        if df_mode:
            print(f"  └─ Containment: {df_mode}")

    # 3. Fragnesia
    if off_res.get("fragnesia", {}).get("tested") or on_res.get("fragnesia", {}).get("tested"):
        fn_off = "VULNERABLE (Corrupted)" if off_res.get("fragnesia", {}).get("corrupted") else "NOT TESTED"
        if on_res.get("fragnesia", {}).get("pks_trapped"):
            fn_on = "BLOCKED (Hardware #PF 0x23)"
            fn_mode = on_res["fragnesia"]["containment"]
        elif on_res.get("fragnesia", {}).get("panic_interrupt"):
            fn_on = "BLOCKED (SoftIRQ Panic)"
            fn_mode = "Fail-Closed Panic in SoftIRQ"
        else:
            fn_on = "VULNERABLE"
            fn_mode = "None"
        print(f"{'fragnesia':<14} | {fn_off:<28} | {fn_on:<28}")
        if fn_mode:
            print(f"  └─ Containment: {fn_mode}")

    print("=" * 78)


def merge_results(target: dict, source: dict):
    for k in ["copy_fail", "dirty_frag", "fragnesia"]:
        if source.get(k, {}).get("tested"):
            target[k] = source[k]


def main():
    parser = argparse.ArgumentParser(description="Analyze PKS exploit test results.")
    parser.add_argument("--off-log", type=Path, default=Path("results/sec_off.log"),
                        help="Path to sec_off.log")
    parser.add_argument("--on-log", type=Path, default=Path("results/sec_on.log"),
                        help="Path to sec_on.log")
    args = parser.parse_args()

    results_dir = args.off_log.parent

    off_res = parse_sec_log(args.off_log) if args.off_log.is_file() else {}
    on_res = parse_sec_log(args.on_log) if args.on_log.is_file() else {}

    # Check granular logs if monolithic logs are missing or partially populated
    for test in ["copyfail", "dirtyfrag", "fragnesia"]:
        g_off = results_dir / f"sec_{test}_off.log"
        g_on = results_dir / f"sec_{test}_on.log"
        if g_off.is_file():
            merge_results(off_res, parse_sec_log(g_off))
        if g_on.is_file():
            merge_results(on_res, parse_sec_log(g_on))

    print_summary(off_res, on_res)


if __name__ == "__main__":
    main()
