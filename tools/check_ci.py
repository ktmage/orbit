#!/usr/bin/env python3
import argparse
import pathlib
import subprocess
import sys

from check_compile_fail import run as check_compile_fail
from check_tests import run as check_tests

ROOT = pathlib.Path(__file__).resolve().parents[1]


def execute(*command):
    subprocess.run(command, cwd=ROOT, check=True, timeout=180)


def verify(target):
    execute("moon", "fmt", "--check")
    execute("actionlint", "-shellcheck=", "-pyflakes=", ".github/workflows/ci.yml")
    execute(sys.executable, "-m", "unittest", "discover", "-s", "tools", "-p", "test_*.py")
    execute(sys.executable, "tools/check_architecture.py")
    check_tests(target)
    check_compile_fail(target)
    execute("moon", "run", "examples/clock", "--target", target, "--deny-warn")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True, choices=["js", "wasm"])
    verify(parser.parse_args().target)
