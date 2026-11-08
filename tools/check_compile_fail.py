#!/usr/bin/env python3
import argparse
import json
import pathlib
import shutil
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]


def check(root, target):
    process = subprocess.run(
        ["moon", "-C", str(root), "check", "--target", target, "--output-json", "--frozen"],
        text=True, capture_output=True,
    )
    diagnostics = []
    for line in process.stdout.splitlines():
        try:
            message = json.loads(line)
        except ValueError:
            continue
        if message.get("level") == "error":
            diagnostics.append(message)
    return process, diagnostics


def run(target):
    fixtures = sorted((ROOT / "tests/compile_fail").glob("*.mbt.txt"))
    if not fixtures:
        raise RuntimeError("型エラーの検査対象がありません。")
    with tempfile.TemporaryDirectory(prefix="orbit-compile-fail-") as temporary:
        root = pathlib.Path(temporary).resolve() / "orbit"
        shutil.copytree(ROOT, root, ignore=shutil.ignore_patterns(".git", ".docs", "_build", ".mooncakes", "__pycache__"))
        (root / ".mooncakes").symlink_to(ROOT / ".mooncakes", target_is_directory=True)
        probe = root / "compile_probe"
        probe.mkdir()
        for fixture in fixtures:
            expected = json.loads(fixture.with_suffix("").with_suffix(".json").read_text())
            (probe / "moon.pkg").write_text(expected["package"])
            source = probe / "fixture.mbt"
            source.write_text(expected["valid_source"])
            baseline, baseline_errors = check(root, target)
            if baseline.returncode != 0 or baseline_errors:
                raise RuntimeError(f"{fixture.name}: 正しいコードの検査に失敗しました。\n{baseline.stdout}\n{baseline.stderr}")
            source.write_text(fixture.read_text())
            result, errors = check(root, target)
            actual = sorted((error["error_code"], int(error["loc"].split(":")[0]))
                            for error in errors if pathlib.Path(error["path"]).resolve() == source)
            wanted = sorted((error["code"], error["line"]) for error in expected["errors"])
            if result.returncode == 0 or actual != wanted or len(errors) != len(wanted):
                raise RuntimeError(f"{fixture.name}: 想定した型エラーと一致しません。\n{result.stdout}\n{result.stderr}")
            source.unlink()
            print(f"{target}: {fixture.name}: 期待したコンパイルエラーを確認しました。")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True, choices=["js", "wasm"])
    run(parser.parse_args().target)
