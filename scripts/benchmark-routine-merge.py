#!/usr/bin/env python3
"""Compile an optimized core benchmark and report five-run medians as CSV."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source-root', type=Path, default=ROOT,
                    help='Checkout containing the core sources to measure (default: this checkout)')
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='dotlist-merge-benchmark-') as directory:
    binary = Path(directory) / 'routine-merge'
    subprocess.run(['swiftc', '-O', '-whole-module-optimization', '-swift-version', '5',
                    '-strict-concurrency=complete', '-warnings-as-errors',
                    *map(str, sorted((args.source_root / 'Sources/DotListPlusCore').glob('*.swift'))),
                    str(ROOT / 'benchmarks/RoutineMerge.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
