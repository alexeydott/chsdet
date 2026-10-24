# Supplementary Free Pascal execution

These probes execute the production Pascal detector in Free Pascal 3.2.2 on
Linux x86-64. They **do not establish Delphi Win32/Win64 compilation or DUnitX
success**. In particular, expression promotion, RTL encodings and exception
details can differ. The Delphi range/overflow matrix remains the primary gate.

`run.py` copies top-level `.pas`/`.inc` sources into a build directory and removes
only the `System.` namespace prefix from `SysUtils`, `TypInfo` and `Classes`.
It never rewrites detector algorithms. The exact compiler command, SHA-256
hashes of the input sources and harness, and the list of namespace replacements
are saved in `build.json`; diagnostics go to
`build.log`. Supply an installed compiler and its matching RTL unit directory.

```sh
python3 tests/portable/run.py \
  --source . --build ../build-fpc \
  --compiler /path/to/ppcx64 \
  --rtl /path/to/fpc/3.2.2/units/x86_64-linux/rtl
python3 tests/portable/regressions.py \
  --probe ../build-fpc/CoreProbe --output ../build-fpc/regressions
```

The default corpus run checks every manifest row at chunk sizes `0` (whole
input), `1`, `2`, `3`, `7`, `64`, and `8192`. Strict rows require the exact code
page **and** name from the checked-in manifest. Informational rows are recorded
but do not fail the run. Every run emits `corpus-results.json`. Chunk-dependent
failures are reported, not silently accepted as baseline behavior.

`regressions.py` independently creates UTF-16 ASCII payloads from explicit byte
pairs, a literal `0xA0` NBSP payload, unpaired UTF-16 surrogates and odd byte
lengths, valid UTF-8 scalar sequences, malformed UTF-8 suffixes, and
disabled-encoding cases. It also appends a literal four-byte GB18030
discriminator to the existing GBK corpus fixture and checks the compatible
GB18030 candidate after disabling GBK/936. An optional `--corpus` argument
selects the corpus directory; it defaults to this repository's `corpus/data`.
The detector implementation is always
the compiled Pascal code, not a Python translation. Results go to `results.json`.

For an isolated before/after comparison, export the original revision to another
directory and run the **same harness** with that directory as `--source`. Never
replace source files in a working checkout to produce a baseline.

The command-line probe is also useful for one concrete case:

```sh
../build-fpc/CoreProbe /path/to/input.bin 1
../build-fpc/CoreProbe /path/to/input.bin 7 65001
```

Its output is `codepage<TAB>name<TAB>language<TAB>confidence<TAB>BOM enum`.
The optional third argument disables one code page before feeding input.

`WrapperProbe.dpr` checks that an overflowing `Offset/Count` request raises
`EArgumentOutOfRangeException` and that valid ASCII input remains detectable
after the rejected request. It also checks refusal of incompatible UTF-32
decoders for unusual UCS-4 byte orders, preservation of an explicit fallback,
reset after incomplete UTF-8, and the EUC-TW Windows code-page identifier.
It checks that `Finish` is terminal until `Reset`, including empty input, and
protects whole-buffer Windows-1251 detection of a mixed ASCII/Cyrillic word
against changes in BOM-prefix replay.
Compile a standalone probe with:

```sh
python3 tests/portable/run.py \
  --source . --build ../build-wrapper \
  --compiler /path/to/ppcx64 \
  --rtl /path/to/fpc/3.2.2/units/x86_64-linux/rtl \
  --program tests/portable/WrapperProbe.dpr --build-only
../build-wrapper/WrapperProbe
```

On the original revision, FPC x86-64 already passes the overflow bounds check.
That one check is therefore supplementary contract coverage, **not** proof that
Delphi's overflow defect was reproduced under FPC. Never run an unchecked overflow reproduction
against an implementation that may read beyond the supplied buffer.

`ProberProbe.dpr` uses the same literal scenarios as `ChsDet.ProberTests.pas`:
GB18030 identity after confidence queries, final-state return values, UTF-16
word alignment at every split, retention of a word containing byte `0x80`,
two-byte UTF-16LE character lengths for all possible first bytes, and identical
single-byte model scores for the complete Windows-1251 corpus at every chunk
size, monotonic saturation of confidence, consumption of split Japanese
characters, and exact input bounds protected by a Linux `mprotect` guard page.
Its two subclasses only expose
protected preparation seams: registering the real production UTF-8 model, or
supplying attainable pair counters to the real confidence method. No detector
behavior is replaced with a fake. Build it with
the standalone command above, substituting `ProberProbe.dpr`, then run
`../build-wrapper/ProberProbe tests/corpus/data` (or use a separate build
directory). The argument supplies the existing corpus fixture directory.

`StreamingRegression.dpr` checks word and markup boundaries at every split,
reset of pending filter state, undefined Windows-1252 bytes, and small-chunk
Greek/Hebrew corpus detection. Build it through the same `--program` option
and run it with `tests/corpus/data` as its first argument. It reports actual
executed tests and assertion counts and exits nonzero on a failure.
