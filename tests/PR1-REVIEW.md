# Technical review of PR #1 — 2026-10-21 (Moscow)

## Decision and evidence boundary

The five replacements in [PR #1](https://github.com/alexeydott/chsdet/pull/1)
are the right narrowly scoped fix for interpreting static data as dynamic arrays.
The reviewed head is `12c1a78addad6ff91afd32c6929da751e6113324`; reviewed main is
`4660893fb7966f78982ef23fb2fb92215499cbec`.

**Hold merge pending Delphi execution of the added gate.** This environment has
no dcc32, dcc64, FPC, Wine or PowerShell. Neither DUnitX execution, baseline
reproduction nor recognition equivalence was independently run here. The
36-file Delphi 13 Win64 results in the PR body remain the author's results.
GitHub returned no PR-triggered workflow runs for the reviewed head; this is not
a claim that no other checks or external jobs exist.

Source references:

- [Original diff](https://github.com/alexeydott/chsdet/commit/12c1a78addad6ff91afd32c6929da751e6113324)
- [Dynamic array memory format](https://docwiki.embarcadero.com/RADStudio/Athens/en/Internal_Data_Formats_(Delphi))
- [Range checking](https://docwiki.embarcadero.com/RADStudio/Athens/en/Range_checking)
- [Compiler directives and precedence](https://docwiki.embarcadero.com/RADStudio/Athens/en/Delphi_compiler_directives)

## Findings

### Required validation: no deterministic automated proof in the original patch

The existing fixture already covers JP/KR/HZ and the strict corpus, but the
README build does not explicitly set R/Q. The patch adds no regression tests.
Normal static constants have unpredictable preceding bytes, so a test relying
only on their accidental length-header contents can pass even on faulty code.
The added sentinel-backed raw tables address this. Run the **same harness** on
old/new production code and inspect class/location of runtime failures; an old
version compilation failure is not a reproduction.

### Array views fix representation, not allocation bounds

`PPRUInt8Arr` / `PPRInt16Arr` / `PPRUInt32Arr` do not allocate giant objects and
do not read a dynamic length header. They are aliases for accessing existing
memory. The old dynamic types remain available; no record layout, ownership,
allocation or exported function signature changes in the original patch.

With MaxInt = 2147483647, the declared upper indexes/counts/byte sizes are:

| View | Upper index | Element count | Byte size |
| --- | ---: | ---: | ---: |
| Byte | 2147483646 | 2147483647 | 2147483647 |
| Int16 | 1073741822 | 1073741823 | 2147483646 |
| UInt32 | 536870910 | 536870911 | 2147483644 |

The formulas are `count = MaxInt div SizeOf(element)`, `upper = count - 1`,
`bytes = count * SizeOf(element)`. They are unchanged on Win32/Win64: these
fixed-width element types and MaxInt are not pointer-sized. No pointer is
narrowed to Integer. Actual indexes here are much smaller. Changing to
NativeInt-sized giant arrays is unnecessary and is not a fix for actual bounds.
Compilation of these large *types* still needs both Delphi compiler checks.

For a built-in model, `classTable[Byte(c)]` reads 0..255;
`byteCls < classFactor`; next index is
`Cardinal(currentState) * classFactor + byteCls`. Independently traversing all
reachable states, including terminal self-loops, gives:

| Model | Factor | State bytes | Maximum reachable index |
| --- | ---: | ---: | ---: |
| Big5 | 5 | 24 | 19 |
| EUCJP | 6 | 40 | 35 |
| EUCKR | 4 | 16 | 15 |
| EUCTW | 7 | 48 | 41 |
| GB18030 | 7 | 48 | 41 |
| HZ | 6 | 48 | 41 |
| ISO2022CN | 9 | 64 | 49 |
| ISO2022JP | 10 | 72 | 69 |
| ISO2022KR | 6 | 40 | 35 |
| SJIS | 6 | 24 | 22 |
| UCS2BE | 6 | 56 | 53 |
| UCS2LE | 6 | 56 | 53 |
| UTF8 | 16 | 208 | 207 |

Source: included `*LangModel.inc` literals at the reviewed commits and output of
`python tests/audit-tables.py`. This is a finite graph proof for the checked-in
models from Reset, not a proof for arbitrary caller-supplied SMModel records or
corrupted protected state. The DUnitX graph test additionally calls the actual
`NextState` implementation for each reachable state and all 256 bytes; it has
not been executed here.

`CharDistribution.HandleOneChar` already guards `order >= 0` and
`order < Integer(mTableSize)`. The five frequency declarations have exactly
5376 (Big5), 2352 (EUCKR), 5376 (EUCTW), 3760 (GB2312), 4368 (JIS) Int16
initializers. Constructors pair their pointer and corresponding size, so the
new view preserves the existing bound guard. Byte-pair order formulas use small
integer operands (up to byte values); they cannot overflow 32-bit arithmetic.
The synthetic test checks -1, first, last and one-past-last order, and 511/512
frequency threshold, with a canary after the table.

### Existing type mismatches in charLenTable; not introduced by PR

HZ/KR/CN and JP tables are PRUint32 arrays but NextState reads bytes. All entries
are zero, so current byte reads return the intended zero. JP has eight declared
UInt32 elements but ten classes: indexes 8/9 remain inside its **32-byte**
allocation, although they do not index the intended elements. Do not casually
change the access to UInt32: the other models have actual Byte arrays.

Recommended cleanup: standardize these four ESC tables to Byte, and make JP ten
zero entries. This preserves the values read by existing code. Standardize
UCS2LE separately, with a dedicated GetCurrentCharLen regression: its UInt32
`(2,2,2,2,2,2)` is read as bytes `2,0,0,0,2,0` on Windows, so some classes return
zero. This is a pre-existing semantic error. Changing it could affect consumers
of GetCurrentCharLen and should not be hidden in a cast-only patch. Production
cleanup is intentionally not mixed into this test companion.

### Existing API limitations and long-stream risks

`SMModel` carries no sizes; public Create accepts arbitrary pointers and factors.
The PR's upper bounds do not validate these records. If untrusted/custom models
are a supported contract, add actual table lengths, validate nil pointers,
class/factor/index relationships using widened arithmetic, and define failure
behavior. That changes record layout and initialization sites and deserves an
explicit API change. It is not required to preserve the current built-in model
behavior established by the literal graph audit.

`GETFROMPCK` has no in-repository callers outside its own declaration/definition
before these tests. With its declared 4-bit settings, it reads word `i shr 3`,
shift `(i and 7) shl 2` (0..28), masks with 15, and returns 0..15. The shift is
unsigned because the table element is Cardinal, including $FEDCBA98. There is
no arithmetic overflow for valid nonnegative bounded indexes. Parenthesize the
shift explicitly if editing for readability; preserve Delphi's current
operator grouping. Test uses literal words and expected nibbles 0..15, never a
round trip through PCK4BITS as the only oracle.

It has no actual word count and invalid/nil input is not safe. Negative i must
not be assumed rejected by the huge view: a logical shift can produce a
positive index within its declared range. If exposing it as a general API,
require and validate i >= 0 plus a real word count before any dereference.

Q+ does not provide table bounds or pointer validity. Reachable state indexes
fit Cardinal. The existing mCurrentBytePos, mTotalChars and mFreqChars counters
can overflow on sufficiently long repeated use; the cast patch neither causes
nor fixes this. NextState also uses nsSMState with nonterminal table values
above its named 0..2 enumerators. The explicit cast is retained; the compiler
matrix must exercise these values under R+ rather than treating them as invalid
model states merely because they have no enum names.

An additional existing streaming issue is visible in nsUniversalDetector:
when HZ `~` is the final byte of one pure-ASCII chunk and `{` starts the next,
the wrapper recognizes the pair using mLastChar but feeds the ESC prober only
the new chunk. The prober did not see the previous `~`. The added split tests
therefore explicitly cover the prober, not an unsupported claim of universal
wrapper chunk invariance. A wrapper replay fix needs its own regression and
recognition comparison; this is not an effect of the five casts.

## Added coverage and how to validate

- Four registered DUnitX table tests: all 13 reachable state graphs/all bytes;
  sentinel-backed Byte reads (all three sites); packed Cardinal words/high bit;
  guarded Int16 frequency reads and reset.
- Two tests in the existing fixture: exact identities and 0.99 confidence for
  literal ESC files; all two-chunk split positions at prober level, truncated
  prefixes and repeated reset/reuse across JP/KR/HZ.
- Three raw byte corpus files and generator entries, raising strict cases
  from 36 to 39. Existing 36 rows and data are retained.
- Minimal sequences independently traverse to eItsMe:
  JP `ESC $ B` => 3,4,2; KR `ESC $ ) C` => 3,4,5,2;
  HZ `~{VPND~}` => 3,4,5,4,5,4,6,2. These traces were evaluated in Python,
  not by the Delphi wrapper.
- Full mode/platform build script, XML discovery checks, exact snapshot export
  and isolated old/new comparison, documented in tests/README.md.

Run both PowerShell scripts from a configured Delphi environment. Require all
existing/new DUnitX cases to execute and pass on Win32/Win64 with R+/Q+, and
confirm no failures in the other six combinations. Compare snapshots from main
R-/Q- and fixed R-/Q- on each architecture, including all informational rows,
identity, language, BOM and exact Double bits (not rounded matrix confidence).
The old-version three sentinel tests must fail at runtime with range errors.

Actual local checks: literal graph/frequency audit passed; three ESC traces
reached acceptance; `git diff --check` passed. No Delphi build/run or numeric
coverage percentage is claimed. Handwritten corpus is not statistical encoding
accuracy coverage, fuzzing, malformed model validation or a long-stream test.

Once compiler/runtime and equivalence evidence is attached, the original
representation fix is suitable for merging with these tests. Until then,
GitHub's mergeable=true is only a conflict-status signal, not validation.
