#!/usr/bin/env python3
"""Exercise the compiled detector with independently specified byte fixtures.

The Python code creates input bytes and checks output only. All detection runs
in the Pascal production code compiled by run.py.
"""

import argparse
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--corpus", type=Path,
                        default=Path(__file__).resolve().parents[1] / "corpus/data",
                        help="Existing corpus data directory (for GBK compatibility cases)")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    ascii_text = (b"Plain ASCII words with spaces and punctuation. "
                  b"The quick brown fox jumps over the lazy dog.\n") * 12
    utf16le = b"".join(bytes((value, 0)) for value in ascii_text)
    utf16be = b"".join(bytes((0, value)) for value in ascii_text)
    # Literal RFC 3629 UTF-8 scalars: U+041F U+0440 and U+1F642.
    utf8 = (b"UTF-8 text: \xd0\x9f\xd1\x80 \xf0\x9f\x99\x82.\n") * 16
    gbk = (args.corpus / "legacy-overlap-gbk.txt").read_bytes()
    if not gbk:
        raise ValueError("The GBK corpus fixture is empty")
    cases = [
        ("utf16le_ascii_without_bom", utf16le, 1200, "UTF-16LE", None, None),
        ("utf16be_ascii_without_bom", utf16be, 1201, "UTF-16BE", None, None),
        ("utf16le_unpaired_high_surrogate", utf16le + b"\x00\xd8",
         None, None, 1200, None),
        ("utf16be_unpaired_high_surrogate", utf16be + b"\xd8\x00",
         None, None, 1201, None),
        ("utf16le_odd_length", utf16le + b"X", None, None, 1200, None),
        ("utf16be_odd_length", utf16be + b"X", None, None, 1201, None),
        ("nbsp_is_not_ascii", (b"Text with nonbreaking\xa0spaces. ") * 12,
         1252, "windows-1252", None, None),
        ("valid_utf8_four_byte_scalar", utf8, 65001, "UTF-8", None, None),
        ("utf8_late_invalid_byte", utf8 + b"\xff", None, None, 65001, None),
        ("utf8_truncated_scalar", utf8 + b"\xf0\x9f", None, None, 65001, None),
        ("disabled_utf16le_is_not_returned", utf16le, None, None, 1200, 1200),
        ("disabled_utf16be_is_not_returned", utf16be, None, None, 1201, 1201),
        ("disabled_utf8_is_not_returned", utf8, None, None, 65001, 65001),
        ("disabled_ascii_is_unknown", ascii_text, -1, "Unknown", None, 0),
        ("late_gb18030_discriminator", gbk + b"\x81\x30\x81\x30",
         54936, "GB18030", None, None),
        ("disabled_gbk_retains_gb18030_candidate", gbk,
         54936, "GB18030", None, 936),
    ]
    rows = []
    for name, data, expected_cp, expected_name, forbidden_cp, disabled_cp in cases:
        path = output / (name + ".bin")
        path.write_bytes(data)
        for chunk in (0, 1, 2, 3, 7, 64, 8192):
            command = [str(args.probe.resolve()), str(path), str(chunk)]
            if disabled_cp is not None:
                command.append(str(disabled_cp))
            result = subprocess.run(command, text=True, capture_output=True)
            fields = result.stdout.strip().split("\t")
            actual_cp = int(fields[0]) if result.returncode == 0 and len(fields) == 5 else None
            passed = (result.returncode == 0 and len(fields) == 5)
            if expected_cp is not None:
                passed = passed and actual_cp == expected_cp and fields[1] == expected_name
            if forbidden_cp is not None:
                passed = passed and actual_cp != forbidden_cp
            rows.append({"name": name, "chunk": chunk,
                         "expected_codepage": expected_cp, "expected_name": expected_name,
                         "forbidden_codepage": forbidden_cp, "disabled_codepage": disabled_cp,
                         "passed": bool(passed), "returncode": result.returncode,
                         "actual": fields, "stderr": result.stderr.strip()})
            if not passed:
                print("FAIL", name, "chunk=" + str(chunk),
                      result.stdout.strip(), result.stderr.strip())
    (output / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
    passed = sum(row["passed"] for row in rows)
    print(f"Regression cases: {passed}/{len(rows)}")
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
