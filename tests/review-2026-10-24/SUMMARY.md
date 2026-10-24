# Executed supplementary regression evidence — 2026-10-24

## Scope and limitations

The baseline is the repository's `main` commit
[`853682b06e06f5a4abcd6206c142ffa6e77b900a`](https://github.com/alexeydott/chsdet/commit/853682b06e06f5a4abcd6206c142ffa6e77b900a).
It was exported to an isolated directory before any production edits. The same
test source is compiled against the baseline and the changed sources.

The executed compiler is **Free Pascal 3.2.2**, Linux x86-64, Delphi language
mode, with range and overflow checks enabled (`-Mdelphi -Cr -Co`). Production
units are copied to an isolated build directory. The only compatibility change
is removal of the `System.` prefix in `SysUtils`, `TypInfo`, and `Classes` uses.
Detector algorithms are neither translated to Python nor replaced with mocks.
Build metadata records the actual commands and source/harness SHA-256 hashes.

**These results do not establish compilation or execution in Delphi
Win32/Win64.** The DUnitX fixtures and the existing eight-configuration Delphi
range/overflow gate must still run in RAD Studio. FPC's expression promotion
and RTL encodings differ: the overflowing `Feed(Bytes, 1, MaxInt)` contract
check already passes in FPC on the original version, so that test is not a
reproduction of a Delphi integer-overflow failure.

## Baseline results

| Executed set | Baseline result | Evidence |
| --- | ---: | --- |
| Existing corpus, 39 strict files at seven chunk sizes | 270 / 273 passed | [corpus-results.json](baseline/corpus-results.json) |
| Public-core regressions, 16 scenarios at seven chunk sizes | 59 / 112 passed | [regressions.json](baseline/regressions.json) |
| Direct prober regressions | 0 / 9 passed | [prober.log](baseline/prober.log) |
| Wrapper and public code-page mapping checks | 3 / 7 passed | [wrapper.log](baseline/wrapper.log) |
| Streaming filter and corpus regressions | 2 / 6 passed; 53 assertions reached | [streaming.log](baseline/streaming.log) |

The corpus failures are the byte-by-byte (`chunk = 1`) variants of
`windows-1251.txt`, `windows-1253-no-c1.txt`, and `iso-8859-8.txt`. The other
strict combinations pass on the baseline. There are also two informational
manifest rows at seven chunk sizes, recorded in the JSON but excluded from
the strict denominator.

Of the 53 failing public-core combinations, 42 cover six scenarios at seven chunk
sizes: ASCII-only UTF-16LE/BE without BOM, unpaired UTF-16LE/BE high surrogates,
NBSP incorrectly reported as ASCII, and disabled ASCII still returned. The
odd-length UTF-16 negative cases and UTF-8 cases already pass on the baseline.
The remaining 11 failures cover a late four-byte GB18030 discriminator after
the existing GBK fixture (four failing chunk sizes) and disabling GBK/936 while
leaving its compatible GB18030 family enabled (all seven chunk sizes).

All nine prober regressions fail for their intended runtime behavior. These
include non-monotonic confidence saturation and an observed `EAccessViolation`
when the Japanese context analyzer receives exactly one readable lead byte
before an inaccessible memory page. The guard-page test does not catch or
accept that exception as success.

The four failing wrapper cases are separate checks for UCS-4 byte orders
2143 and 3412 receiving an incompatible ordinary UTF-32 decoder, and EUC-TW
being assigned Windows code page 51936 instead of 51950, plus `Finish` failing
to finalize empty input. The code-page oracle is Microsoft's
[Code Page Identifiers](https://learn.microsoft.com/en-us/windows/win32/intl/code-page-identifiers).
Overflow bounds, reset after incomplete UTF-8, and a whole mixed
ASCII/Cyrillic word retaining Windows-1251 pass on both versions. The last case
also prevents reintroducing an intermediate prefix-replay regression found
and removed during review.

## Final integration status

The final combined run was rebuilt after the last production correction.
All four compiled targets used matching production-source SHA-256 maps, and
those maps were checked against the working tree after the run. Baseline and
final harness hashes also match. Exact commands and hashes are retained in
`baseline/*-build.json` and `final/*-build.json`.

| Executed set | Final result | Evidence |
| --- | ---: | --- |
| Existing strict corpus across seven chunk sizes | 273 / 273 passed | [corpus-results.json](final/corpus-results.json), [log](final/corpus.log) |
| Public-core regressions across seven chunk sizes | 112 / 112 passed | [regressions.json](final/regressions.json), [log](final/regressions.log) |
| Direct prober regressions | 9 / 9 passed | [prober.log](final/prober.log) |
| Wrapper and code-page mapping checks | 7 / 7 passed | [wrapper.log](final/wrapper.log) |
| Streaming regressions | 6 / 6 passed; 2,271 assertions | [streaming.log](final/streaming.log) |

Each final executed set returned exit code 0. The baseline failing sets returned
exit code 1 for actual runtime assertion failures or the guard-page access
violation, not compilation errors. The final direct prober test runs both
Shift_JIS and EUC-JP cases, including valid data after an incomplete character.

The sets overlap and deliberately reuse existing fixtures. These numbers are
regression checks, **not an estimate of recognition accuracy on unseen text**.
The curated corpus does not establish broad language balance, short-text
accuracy, or probability calibration. Delphi-specific results remain unverified.

## Reproduce

The compiler and RTL used for this run were unpacked without installing them
system-wide from the official Debian archive packages:

- `https://deb.debian.org/debian/pool/main/f/fpc/fp-compiler-3.2.2_3.2.2+dfsg-20_amd64.deb`
- `https://deb.debian.org/debian/pool/main/f/fpc/fp-units-rtl-3.2.2_3.2.2+dfsg-20_amd64.deb`

The exact compiler command for each standalone probe is retained in the
adjacent `*-build.json`. In this workspace the compiler and unit directory are:

```sh
TASK_FPC=/workspace/scratch/8ec0f9f52ed3/fpc/usr/lib/x86_64-linux-gnu/fpc/3.2.2/ppcx64
TASK_RTL=/workspace/scratch/8ec0f9f52ed3/fpc/usr/lib/x86_64-linux-gnu/fpc/3.2.2/units/x86_64-linux/rtl
```

From the repository directory, compile and execute the corpus/public API checks:

```sh
python3 tests/portable/run.py --source . --build ../build-fpc \
  --compiler "$TASK_FPC" --rtl "$TASK_RTL"
python3 tests/portable/regressions.py --probe ../build-fpc/CoreProbe \
  --output ../build-fpc/regressions
```

Compile each standalone probe with the same source transformation and flags,
then execute the produced binary. For example:

```sh
python3 tests/portable/run.py --source . --build ../build-prober \
  --compiler "$TASK_FPC" --rtl "$TASK_RTL" \
  --program tests/portable/ProberProbe.dpr --build-only
../build-prober/ProberProbe tests/corpus/data
```

Repeat that command with `WrapperProbe.dpr` / `WrapperProbe` and
`StreamingRegression.dpr` / `StreamingRegression` in their own build
directories. `WrapperProbe` needs no corpus argument; `StreamingRegression`
takes the same `tests/corpus/data` argument. To reproduce the baseline, pass the
isolated exported baseline directory as `--source`, while keeping these same
harness files.

The input chunk sizes are `0` (one whole block), `1`, `2`, `3`, `7`, `64`, and
`8192`. Assertions compare code page and charset name with the checked-in
manifest, literal byte contracts, or equivalent complete-input statistics.
The corpus runner rejects an empty chunk list or a manifest with no strict
cases; zero executed tests cannot produce a successful corpus result.
