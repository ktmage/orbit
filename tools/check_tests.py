#!/usr/bin/env python3
import argparse
import pathlib
import re
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[1]


def verify_counts(outline, result):
    expected = len(re.findall(r"^\s*\d+\. .* index=\d+", outline, re.MULTILINE))
    totals = re.findall(r"Total tests: (\d+), passed: (\d+), failed: (\d+)\.", result)
    if not expected or len(totals) != 1:
        raise RuntimeError("テストの予定件数または完了件数を取得できませんでした。")
    total, passed, failed = map(int, totals[0])
    if total != expected or passed != expected or failed != 0:
        raise RuntimeError(f"予定した{expected}件に対し、完了{total}件・成功{passed}件・失敗{failed}件です。")
    return expected


def run(target):
    command = ["moon", "-C", str(ROOT), "test", "--target", target, "--deny-warn"]
    outline = subprocess.run(command + ["--outline"], text=True, capture_output=True, check=True)
    result = subprocess.run(command, text=True, capture_output=True, timeout=120)
    print(result.stdout, end="")
    print(result.stderr, end="")
    result.check_returncode()
    count = verify_counts(outline.stdout + outline.stderr, result.stdout + result.stderr)
    print(f"{target}: 予定した{count}件すべての完了を確認しました。")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True, choices=["js", "wasm"])
    run(parser.parse_args().target)
