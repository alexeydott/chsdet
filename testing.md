# Testing

This project now includes a DUnitX test runner in `ChsDetTests.dpr` and the main fixture in `tests/ChsDet.Tests.pas`.

The October 2026 detection review adds 27 substantive DUnitX methods in
`tests/ChsDet.RegressionTests.pas`, `tests/ChsDet.ProberTests.pas`, and
`tests/ChsDet.StreamingTests.pas`. These cover exact outputs, malformed tails,
model scores, state transitions, byte filtering, reset and guard-page memory
boundaries. They are explicitly registered and linked by the runner.

Run `tests/run-range-matrix.ps1` for the Delphi Win32/Win64 R/Q matrix. It also
checks that the new fixtures were discovered. The runner fails when no tests
pass, and the matrix rejects missing, ignored or failed cases.

Supplementary Linux/FPC execution and its limitations are documented in
[tests/portable/README.md](tests/portable/README.md). The actual before/after
evidence and research plan are in
[the review report](tests/review-2026-10-24/REPORT.ru.md).

The repository also includes a corpus benchmark:

- `ChsDetCorpusBench.dpr`
- `tests/corpus/manifest.tsv`
- `tests/corpus/README.md`
- `tests/corpus/MATRIX.md`

## Covered Scenarios

- `ASCII` detection from raw bytes
- `UTF-8` with BOM and `GetEncoding`
- `UTF-8` without BOM
- `UTF-16LE` with BOM
- `UTF-16BE` through the fluent stream API
- `windows-1251` from a temporary file
- `windows-1252` from raw bytes
- `windows-1252` with a `0x80` Euro-sign-heavy sample
- `windows-1253` promotion when C1 bytes are present
- `windows-1253` without C1 bytes when non-C1 Greek discriminator bytes are present
- `IBM866` via chunked incremental input
- `ISO-8859-8` from a visual Hebrew corpus sample
- `Shift_JIS` from raw bytes
- `EUC-JP` from raw bytes
- `GB18030` via chunked incremental input
- `Big5` from raw bytes
- `ISO-2022-JP` from a fixture file
- `EUC-KR` from a fixture file
- `ISO-2022-KR` from raw bytes
- `ISO-2022-CN` from a corpus fixture with chunked incremental input
- `HZ-GB-2312` from raw bytes
- `GetEncodingDef` fallback behavior

The tests also exercise the wrapper entry points for bytes, streams, files, and the fluent facade.

## Build and Run

Win32:

```powershell
Path/to/dcc32.exe -B -Ebin32 -N0bin32 ChsDetTests.dpr
bin32\ChsDetTests.exe
```

Win64:

```powershell
Path/to/dcc64.exe -B -Ebin64 -N0bin64 ChsDetTests.dpr
bin64\ChsDetTests.exe
```

Corpus benchmark:

```powershell
Path/to/dcc32.exe -B ChsDetCorpusBench.dpr
.\ChsDetCorpusBench.exe
```

The benchmark writes a fresh Markdown accuracy matrix to `tests/corpus/MATRIX.md`.

## Test Design Notes

### Delphi 12 PR #3 Blocker Validation

The blocker fixes were validated with Delphi compiler 36.0 on Win32 and Win64,
with all four combinations of range checking (`R+`/`R-`) and overflow checking
(`Q+`/`Q-`). Each of the eight configurations passed all 82 tests, with no
ignored tests or errors. Recognition snapshots matched across R/Q modes within
each platform; cross-platform floating-point bit identity is not asserted.

The MBCS regression feeds a high-confidence Shift_JIS prefix followed by a tail
rejected by its state machine, using chunk sizes 1, 2, 7, 1200 and 1202. Both the
prober and public wrapper must discard that candidate. Statistical shortcuts
no longer skip the remainder of a block or inherit structural certainty.
The existing GB18030 structural-signature/reset test remains in place.

The UTF-16 fixture builder clears its managed result before allocation, so
successive endian cases cannot retain bytes from the previously returned array.

Reproduce the complete native matrix:

```powershell
./tests/run-range-matrix.ps1 `
  -Compiler32 'D:\Embarcadero RAD Studio\23.0\bin\dcc32.exe' `
  -Compiler64 'D:\Embarcadero RAD Studio\23.0\bin\dcc64.exe'
```

### Mixed SBCS Word Streaming

The SBCS filter preserves unfinished ASCII prefixes across input blocks. Once a
word contains a byte at or above `0x80`, its exact prefix statistics are committed
before the remaining bytes. Delimiters discard ASCII-only words
and normalize the end of a retained word to a single space. `Reset` clears all
pending filter state; confidence queries do not flush an unfinished word.
The universal detector forwards ASCII-only blocks to the SBCS filter too.

Four targeted regressions compare all 13 SBCS child models at every split of
short mixed-word inputs, exercise an 8193-byte ASCII prefix with small chunks,
check delimiter/reset behavior, and require the independently labelled CP1251
public-API sample to retain its code page and confidence across every split.
They also cover an unterminated word at EOF and trailing ASCII-only words.

The filter retains no variable-length prefix buffer. Each language model has a
fixed-size summary of character/frequency counts, bigram categories and the
first/last character orders. Committing adds the single bigram at the join,
including reversed models. The Hebrew final-letter analyzer needs only the last
two ASCII letters: ASCII contains no Hebrew final forms. Pending summaries take
less than 1 KiB in total, independent of word length. No truncation or confidence
correction is applied, and queries do not commit pending statistics.

Sequence counters use `UInt64`, including live model counters, so a long prefix
does not hit the former 32-bit counting limit. As with any fixed-width counter,
the representable count remains finite; this is not arbitrary-precision input
accounting. Three additional regressions enforce bounded allocation while
streaming 2 MiB, exact model-summary joins, and counts beyond `2^32`.

Delphi 12 Win32 and Win64 validation passes all 89 tests in every R/Q combination,
with matching recognition snapshots across R/Q modes within each platform.

### General Notes

- The suite uses repeated phrases instead of tiny samples to keep statistical detection stable
- File-based tests write temporary files and clean them up after each run
- Encoding-specific samples are generated with `TEncoding.GetEncoding(...)`, including `1251`, `1252`, `866`, and `932`
- Unicode BOM tests prepend the RTL preamble before the payload
- CJK coverage beyond `Shift_JIS` uses checked-in byte fixtures for encodings where Delphi RTL byte generation is not reliable enough for detector validation
- The corpus benchmark also includes informational ambiguity rows that are intentionally not enforced as hard failures

## What the Tests Protect

- The Delphi 12 wrapper stays byte-oriented
- BOM mapping remains correct
- `GetEncoding` and `GetEncodingDef` behave predictably
- the fluent adapter remains equivalent to the direct wrapper
- the Windows-1252 regression does not fall back into a false Unicode result
- UTF-8 detection works for non-BOM multibyte samples
- multibyte state handling remains correct for `EUC-JP` and `GB18030`
- the strict corpus benchmark remains exact across the checked-in family fixtures

## Gaps

- The corpus benchmark is intentionally small and curated rather than broad or language-balanced
- Logical Hebrew without distinctive bytes remains ambiguous between `windows-1255` and `ISO-8859-8-I`-style content
- Greek byte streams without C1 bytes and without non-C1 discriminator bytes remain ambiguous between `windows-1253` and `ISO-8859-7`
- Latin-1-like Western text remains collapsed into `windows-1252`, because `ISO-8859-1` is not currently exposed as a separate detector result
- Very short or highly ambiguous UTF-8 without BOM samples can still remain `Unknown`
- The small generated corpus measures regressions, not population-wide accuracy.
