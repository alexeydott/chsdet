# Testing

This project now includes a DUnitX test runner in `ChsDetTests.dpr` and the main fixture in `tests/ChsDet.Tests.pas`.

The current recognition and streaming regressions comprise 54 DUnitX methods in
`tests/ChsDet.RegressionTests.pas`, `tests/ChsDet.ProberTests.pas`, and
`tests/ChsDet.StreamingTests.pas`. These cover exact outputs, malformed tails,
model scores, exact bounded summaries, 64-bit sequence counts, state transitions,
byte filtering, reset and guard-page memory boundaries. They are explicitly
registered and linked by the runner; the full suite currently contains 108 tests.

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

Delphi 12 Win32 and Win64 validation passes all 108 tests in every R/Q combination,
with matching recognition snapshots across R/Q modes within each platform.

### MBCS Syntax and End-of-Input Audit

MBCS state machines now consume all original bytes, including ASCII. Previously,
filtering `81 30 20 81 30` removed the space and invented the valid-looking
GB18030 sequence `81 30 81 30`; results could also vary with chunk boundaries.

A GB18030 four-byte signature preserves family evidence but does not stop syntax
validation. The machine resumes at a character boundary and can reject a later
invalid suffix. An incomplete character is temporarily ineligible for candidate
selection, including after a strong statistical Shift_JIS prefix. Querying
confidence does not finalize the stream, and completing the pending character
restores an otherwise valid candidate.

Three native regressions failed on the previous implementation and pass after
these changes. They cover every two-block split of six malformed/incomplete
GB18030 suffix cases, artificial signatures caused by ASCII deletion, public API
results, and successful resumption after an incomplete tail. The original strict
corpus and valid structural-signature/reset checks remain enforced.

### BOM-less Unicode and OEM False Positives

BOM-less UTF-16 needs text plausibility in addition to alignment and surrogate
validity. Both the zero-parity heuristic and Unicode-prober result selection
normally reject a candidate when more than 2% of decoded code units are C0/C1 controls.
TAB through CR and Unicode NEL are treated as text whitespace. Sparse controls,
such as an isolated terminal ESC in an otherwise textual input, remain allowed.
This explicit conservative policy is not an empirically calibrated probability;
BOM-based detection remains unchanged, and this is not a general binary filter.
To avoid excluding short text, up to two controls are also allowed when at least
four other code units are present. The zero-parity path accepts inputs from eight
bytes rather than reusing the unrelated 128-byte OEM minimum. Both endian orders
of short accented text with embedded NUL or ANSI-style ESC controls are tested.

OEM850/858 and OEM852 signatures must include at least two different supporting
byte values, unless at least 20 supporting accents occur between ASCII letters.
This word context may bypass the coarse DBCS byte-pair heuristic, but not an
actual winning CJK/Unicode model. OEM art likewise needs two distinct art bytes,
or two graphic rows with runs of at least eight art bytes. The existing art
volume/ratio requirements still apply. The final row may end at EOF. This layout
can outrank repetitive SBCS scores, but never a winning CJK/Unicode model.
An additional guard now prevents either art path from overriding a model above
the minimum reporting threshold when high bytes outside the art set supply
competing text evidence. Matching single- or double-line top and bottom borders
with aligned vertical sides and multiline art layout provide a frame exception, preserving real NFO with
accented text. Pure graphic rows retain their positive coverage.
Counters for layout are bounded and neighbour bytes survive chunk boundaries.

Standalone CP1252-style punctuation (`0x80`, `0x91` through `0x94`, `0x96`,
`0x97`) between non-ASCII-letter boundaries blocks OEM text signatures. It is
also legal in OEM encodings, so this is a conservative preference rather than
proof of CP1252. The pending final byte is checked against EOF as a right boundary.
It prevents repeated in-word OEM-like bytes from overpowering independent euro
or dash evidence. An accent next to an ASCII letter does not trigger this guard.

Repetition alone remains insufficient: the isolated-symbol negative fixtures
still pass. Added positive fixtures cover CP850 c-cedilla words, CP852 a-acute
words, CP858 euro prices, and single-symbol CP437 block rows. These contextual
preferences cannot distinguish byte-identical texts with different intended
encodings; neither diversity nor layout is proof of the original encoding.
The formerly ambiguous mixed-prose regressions now require exact CP1251/CP1252
results. When the bounded evidence buffer overflows, only the SBCS and Latin-1 statistical sample replaces maximal uniform
byte runs of length eight or more with a neutral space. Shorter runs, including
ordinary doubled letters, remain literal. Raw observed-byte statistics, BOM and
Unicode/CJK validation still consume every original byte; source data is never
rewritten. OEM/NFO inference therefore retains its full layout evidence.

The fixed 128-byte evidence buffer retains at most eight copies per uniform run.
If it fits until EOF, these capped runs are fed as literal evidence. Otherwise,
the buffer and subsequent input go through the neutralizing sampler. Extending
one run or a uniform padding tail no longer crosses a physical 128-byte cutoff.
Ambiguous short words may remain unknown rather than acquiring a false Western
label. This remains a conservative sampling policy, not a guarantee of label
stability when new, different evidence fills the buffer.

SBCS/Latin-1 candidates are ineligible if their actual statistical sample contains
no high bytes. Repeated high bytes can all disappear when the evidence buffer
switches to neutralized sampling; the remaining ASCII must not manufacture a
Western label. Tests exercise both sides of the 128-byte evidence boundary,
chunk-independent labels/confidence and Reset after a positive CP1252 result.
Raw Unicode/CJK and contextual OEM decisions remain independent of this guard.

Tests cover 127/128/129-byte transitions, repeats up to 4096 bytes and chunk sizes
from one byte to whole input. Missing bottom borders, missing corners or sides,
and shifted rows cannot trigger the accented-frame exception in CP1251/CP1252
prose. Complete frames retain their positive public-API coverage. Frame recognition
uses constant-size row geometry with eight-column tab stops, CRLF and EOF handling.
Aligned tab/space indentation is accepted; one space is not mistaken for a tab.
Nonprintable bytes other than TAB/CR/LF invalidate the current row's frame proof.
In particular NUL, BS, ESC and DEL are not treated as printable one-column cells.
Public-API regressions combine tab-indented pseudo-frames with CP1251/CP1252 prose
and graphic padding, alongside the equivalent printable positive frame. This is
not an ANSI terminal interpreter; control-bearing frames do not get this exception.
Other OEM art heuristics remain available for unframed art: rejecting the frame
exception alone does not mean that every incomplete NFO must be non-OEM.

The sampler retains a byte and a capped run length, with a fixed 256-byte output
buffer. It does not commit a pending run on an arbitrary chunk boundary: the
next different byte or DataEnd resolves it. Reset clears pending state. This is
an explicit repetition-robust sampling policy, not calibrated confidence, and it
does not remove arbitrary multi-byte periodic repetitions or solve encodings
that share identical bytes. Low-level standalone probers still count the bytes
supplied directly to them; sampling belongs to the universal detector pipeline.

Before correction, native regressions reproduced a binary small-integer array
reported as UTF-16 and repeated CP1252 `0x87` reported as OEM. The resulting
negative tests cover both endian orders, C0/C1 arrays, and CP1252 `0x87`, `0xA0`,
and `0xB0`. Positive UTF-16 control handling and the existing strict OEM/NFO corpus
also pass in all eight native build modes.

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
- BOM and escape-designator results can still terminate early; they identify an encoding family rather than validate the entire decoded payload.
- MBCS checks follow the bundled byte-syntax models, not every assigned-code-point or platform-specific extension rule of a strict decoder.
- The small generated corpus measures regressions, not population-wide accuracy.
