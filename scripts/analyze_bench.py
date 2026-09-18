#!/usr/bin/env python3
"""
scripts/analyze_bench.py - Benchmark normalization and analysis entry point.
"""
import subprocess
import sys
from pathlib import Path


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    parse_script = script_dir / "parse_results.py"
    cmd = [sys.executable, str(parse_script)] + sys.argv[1:]
    return subprocess.call(cmd)


if __name__ == "__main__":
    sys.exit(main())
