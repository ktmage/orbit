#!/usr/bin/env python3
import json
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
DOMAINS = {"dependency", "lifecycle", "service", "event"}


def imports(source):
    tokens = re.findall(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|[A-Za-z_]\w*|[{}]', source)
    tokens = [token for token in tokens if not token.startswith(("//", "/*"))]
    index = 0
    while index < len(tokens):
        if tokens[index:index + 2] != ["import", "{"]:
            index += 1
            continue
        index += 2
        depth = 1
        paths = []
        while index < len(tokens) and depth:
            token = tokens[index]
            depth += (token == "{") - (token == "}")
            if token.startswith('"'):
                paths.append(json.loads(token))
            index += 1
        if tokens[index:index + 1] == ["for"]:
            if tokens[index + 1:index + 2] in [['"test"'], ['"wbtest"']]:
                continue
        yield from paths


def violations(root):
    for manifest in sorted(root.rglob("moon.pkg")):
        relative = manifest.relative_to(root)
        if any(part in {".mooncakes", "_build", ".docs"} for part in relative.parts):
            continue
        package = relative.parent.as_posix()
        for imported in imports(manifest.read_text()):
            if not imported.startswith("ktmage/orbit/"):
                continue
            target = imported.removeprefix("ktmage/orbit/")
            if target.startswith("test_support/") and not package.startswith(("test_support/", "tests/")):
                yield f"{relative}: 製品コードがテスト補助コードを参照しています: {target}"
            if package.startswith("core/"):
                domain = package.split("/")[1]
                allowed = {"identity"}
                if domain == "runtime":
                    allowed |= DOMAINS
                elif domain == "identity":
                    allowed = set()
                if not target.startswith("core/") or target.split("/")[1] not in allowed:
                    yield f"{relative}: 許可されていない依存です: {package} -> {target}"


if __name__ == "__main__":
    errors = list(violations(ROOT))
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        sys.exit(1)
    print("パッケージ間の依存方向を確認しました。")
