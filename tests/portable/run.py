#!/usr/bin/env python3
"""Supplementary Linux/FPC core check; never substitutes for Delphi/DUnitX.

Copies production Pascal units to an isolated build directory, removes only the
Delphi RTL namespace prefixes System.SysUtils/System.TypInfo/System.Classes,
and compiles those copies. No detector algorithm is reimplemented here.
"""

import argparse
import csv
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=pathlib.Path, required=True)
    parser.add_argument("--build", type=pathlib.Path, required=True)
    parser.add_argument("--compiler", type=pathlib.Path, required=True)
    parser.add_argument("--rtl", type=pathlib.Path, required=True)
    parser.add_argument("--checks", choices=("on", "off"), default="on")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--program", type=pathlib.Path,
                        help="Optional standalone Pascal probe (requires --build-only)")
    parser.add_argument("--chunks", default="0,1,2,3,7,64,8192")
    args = parser.parse_args()
    if args.program and not args.build_only:
        parser.error("--program requires --build-only")
    try:
        chunks = [int(value.strip()) for value in args.chunks.split(",")
                  if value.strip()]
    except ValueError:
        parser.error("--chunks must contain comma-separated integers")
    if not chunks or any(chunk < 0 for chunk in chunks):
        parser.error("--chunks must contain at least one nonnegative chunk size")
    source = args.source.resolve()
    build = args.build.resolve()
    build.mkdir(parents=True, exist_ok=True)
    src = build / "src"
    src.mkdir(exist_ok=True)
    units = build / "units"
    units.mkdir(exist_ok=True)
    transformations = []
    source_hashes = {}
    for path in sorted(source.iterdir()):
        if path.suffix.lower() not in (".pas", ".inc"):
            continue
        data = path.read_bytes()
        source_hashes[path.name] = hashlib.sha256(data).hexdigest()
        converted, count = re.subn(
            rb"\bSystem\.(SysUtils|TypInfo|Classes)\b", rb"\1", data
        )
        (src / path.name).write_bytes(converted)
        if count:
            transformations.append({"file": path.name, "namespace_replacements": count})
    harness = (args.program.resolve() if args.program else
               pathlib.Path(__file__).resolve().with_name("CoreProbe.dpr"))
    shutil.copyfile(harness, src / harness.name)
    command = [str(args.compiler.resolve()), "-Mdelphi", "-B", "-gl", "-O1",
               "-Fu" + str(args.rtl.resolve()), "-Fu" + str(src),
               "-Fi" + str(src), "-FU" + str(units), "-FE" + str(build)]
    if args.checks == "on":
        command.extend(["-Cr", "-Co"])
    command.append(str(src / harness.name))
    result = subprocess.run(command, cwd=src, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    (build / "build.log").write_text(result.stdout)
    (build / "build.json").write_text(json.dumps({"command": command,
        "source_directory": str(source), "source_sha256": source_hashes,
        "harness_sha256": hashlib.sha256(harness.read_bytes()).hexdigest(),
        "transformations": transformations, "returncode": result.returncode}, indent=2) + "\n")
    if result.returncode:
        print(result.stdout)
        return result.returncode
    executable = build / harness.stem
    print("Built", executable)
    if args.build_only:
        return 0
    rows = []
    failures = 0
    with (source / "tests/corpus/manifest.tsv").open(newline="", encoding="utf-8-sig") as handle:
        cases = list(csv.DictReader(handle, delimiter="\t"))
    if not any(case["tier"] == "strict" for case in cases):
        raise ValueError("The corpus manifest contains no strict test cases")
    for case in cases:
        for chunk in chunks:
            file = source / "tests/corpus/data" / case["file_name"]
            result = subprocess.run([str(executable), str(file), str(chunk)],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            fields = result.stdout.strip().split("\t")
            match = (result.returncode == 0 and len(fields) == 5
                     and fields[0] == case["expected_codepage"]
                     and fields[1] == case["expected_name"])
            strict = case["tier"] == "strict"
            failures += int(strict and not match)
            rows.append({**case, "chunk": chunk, "passed": match,
                         "returncode": result.returncode, "actual": fields,
                         "stderr": result.stderr.strip()})
            if strict and not match:
                print("FAIL", case["file_name"], "chunk=" + str(chunk),
                      "actual=" + result.stdout.strip(), result.stderr.strip())
    (build / "corpus-results.json").write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n")
    strict_count = sum(row["tier"] == "strict" for row in rows)
    print(f"Strict cases: {strict_count - failures}/{strict_count}; failures: {failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
