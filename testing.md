# Testing

This project now includes a DUnitX test runner in `ChsDetTests.dpr` and the main fixture in `tests/ChsDet.Tests.pas`.

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
