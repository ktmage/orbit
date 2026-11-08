#!/usr/bin/env python3
import argparse
import datetime
import hashlib
import json
import pathlib
import platform
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]


def execute(command):
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=120)
    if result.returncode:
        raise RuntimeError(f"測定のコマンドが失敗しました: {command}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def measure(target):
    built = execute(["moon", "run", "benchmarks/lifecycle", "--target", target, "--release", "--build-only", "--deny-warn"])
    artifacts = json.loads(built)["artifacts_path"]
    if len(artifacts) != 1:
        raise RuntimeError("測定用の実行ファイルを特定できませんでした。")
    if target == "js":
        command = ["node", "--expose-gc", artifacts[0]]
        host = execute(["node", "--version"]).strip()
    else:
        command = ["moonrun", artifacts[0]]
        host = execute(["moonrun", "--version"]).strip()
    rows = [json.loads(line) for line in execute(command).splitlines() if line.startswith("{")]
    expected = {(name, count) for count in [10, 50, 100] for name in ["register_chain", "emit", "emit_first_receiver", "replace_chain", "close_chain"]}
    expected |= {("plugin_wait", 1)} | {("repeated_cycles_memory", count) for count in range(100, 601, 100)}
    if len(rows) != len(expected) or {(row["metric"], row["count"]) for row in rows} != expected:
        raise RuntimeError("予定した測定をすべて完了していません。")
    if any(row["memory_bytes"] <= 0 for row in rows if row["metric"] == "repeated_cycles_memory"):
        raise RuntimeError("メモリの測定値を取得できませんでした。")
    kind = "node_heap_after_gc" if target == "js" else "wasm_linear_memory_capacity"
    return {"target": target, "host": host, "memory_kind": kind, "measurements": rows}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    sources = sorted(path for directory in ["core", "adapters", "benchmarks"] for path in (ROOT / directory).rglob("*") if path.suffix == ".mbt" or path.name == "moon.pkg")
    digest = hashlib.sha256()
    for source in sources + [ROOT / "moon.mod"]:
        digest.update(source.relative_to(ROOT).as_posix().encode())
        digest.update(source.read_bytes())
    report = {
        "measured_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "source_sha256": digest.hexdigest(),
        "system": platform.platform(),
        "compiler": execute(["moon", "version", "--all"]).strip(),
        "runs": [measure(target) for target in ["js", "wasm"]],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(f"両ターゲットで各22件の測定を完了しました: {args.output}")


if __name__ == "__main__":
    main()
