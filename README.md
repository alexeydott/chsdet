# chsdet
chsdet is a Mozilla-based charset detector for Delphi. It detects text encodings from original bytes, streams, or files and returns the charset name, Windows code page, language hint, heuristic confidence, and BOM information. The current native validation target is Delphi 12 on Windows Win32 and Win64.

Use [ChsDet.EncodingDetector.pas](ChsDet.EncodingDetector.pas) or [ChsDet.Fluent.pas](ChsDet.Fluent.pas) directly in your application; no DLL is required. The legacy DLL interface remains available. This repository develops the original [SourceForge project](https://sourceforge.net/projects/chsdet/files/).

## Features
- Byte-oriented core using `AnsiChar` and `PAnsiChar`, with direct and fluent APIs for modern Delphi.
- Incremental BOM and escape-designator handling, malformed UTF-8 tail checks, and BOM-less UTF-16 alignment and surrogate validation.
- Provisional statistical detection until end of input, allowing late GB18030 evidence and rejected MBCS candidates to change the result. MBCS checks retain all original bytes and reject malformed or incomplete suffixes after a strong prefix.
- Chunk-independent SBCS mixed-word statistics with fixed-size ASCII-prefix summaries below 1 KiB and 64-bit sequence counters.
- Conservative OEM discrimination and explicit handling of ambiguous single-byte families.
- Native DUnitX regressions, a reproducible charset corpus, and an eight-configuration Delphi range/overflow gate.

## Integration
Add the repository root to your Delphi project's search path and include `ChsDet.Fluent` or `ChsDet.EncodingDetector` in `uses`. Keep the Pascal units and their `.inc` model files together. DUnitX is needed only to build the tests, not to use the library.
  
## Supported Charsets
The table below is copied from the original [ReadMe.txt](ReadMe.txt) and updated to match the current public detector outputs in this port.
| Code page | Name | Notes |
| ---: | --- | --- |
| 0 | `ASCII` | Pseudo code page used for pure ASCII input. |
| 437 | `IBM437` | DOS/OEM NFO and box/block drawing art. |
| 850 | `IBM850` | DOS Latin-1. |
| 852 | `IBM852` | DOS Central European. |
| 855 | `IBM855` | DOS Cyrillic. |
| 858 | `IBM858` | DOS Latin-1 with euro sign. |
| 866 | `IBM866` | DOS Cyrillic. |
| 932 | `Shift_JIS` | Japanese. |
| 936 | `GBK` | GB18030-compatible input without four-byte sequences. |
| 950 | `Big5` | Traditional Chinese. |
| 1200 | `UTF-16LE` | Unicode with BOM-aware detection. |
| 1201 | `UTF-16BE` | Unicode with BOM-aware detection. |
| 1250 | `windows-1250` | Central European single-byte path. |
| 1251 | `windows-1251` | Cyrillic; public output may be paired with Russian or Bulgarian language hints. |
| 1252 | `windows-1252` | Western European single-byte path. |
| 1253 | `windows-1253` | Greek single-byte path. |
| 1255 | `windows-1255` | Hebrew single-byte path. |
| 10007 | `x-mac-cyrillic` | Mac Cyrillic. |
| 12000 | `X-ISO-10646-UCS-4-2143` | UCS-4 unusual byte order, detected through BOM. |
| 12000 | `UTF-32LE` | Shares code page `12000` with the UCS-4 LE-family alias. |
| 12001 | `X-ISO-10646-UCS-4-3412` | UCS-4 unusual byte order, detected through BOM. |
| 12001 | `UTF-32BE` | Shares code page `12001` with the UCS-4 BE-family alias. |
| 20866 | `KOI8-R` | Cyrillic. |
| 21866 | `KOI8-U` | Ukrainian Cyrillic. |
| 28595 | `ISO-8859-5` | Cyrillic; public output may be paired with Russian or Bulgarian language hints. |
| 28597 | `ISO-8859-7` | Greek. |
| 28598 | `ISO-8859-8` | Hebrew. |
| 50222 | `ISO-2022-JP` | Escape-based Japanese encoding. |
| 50225 | `ISO-2022-KR` | Escape-based Korean encoding. |
| 50227 | `ISO-2022-CN` | Escape-based Chinese encoding. |
| 51932 | `EUC-JP` | Japanese multibyte encoding. |
| 51949 | `EUC-KR` | Korean multibyte encoding. |
| 51950 | `x-euc-tw` | EUC Traditional Chinese; 51936 identifies EUC-CN, not EUC-TW. |
| 52936 | `HZ-GB-2312` | 7-bit Chinese encoding. |
| 54936 | `GB18030` | Simplified Chinese multibyte encoding. |
| 65001 | `UTF-8` | BOM and no-BOM UTF-8 are supported. |

## Quick Start
```pascal
uses
 ChsDet.Fluent;

var
  Detection: TChsDetectionResult;
begin
  Detection := TChsDetect.DetectFile('sample.txt');

  if not Detection.IsUnknown then
    Writeln(Detection.Name, ' (CP ', Detection.CodePage, ')');
end;
```

If you need a `TEncoding` instance from the result:

```pascal
uses
  System.SysUtils,
  ChsDet.Fluent;

var
  Detection: TChsDetectionResult;
  Encoding: TEncoding;
begin
  Detection := TChsDetect.DetectFile('sample.txt');

  if Detection.GetEncoding(Encoding) then
  begin
    try
      Writeln(Encoding.EncodingName);
    finally
      if not TEncoding.IsStandardEncoding(Encoding) then
        Encoding.Free;
    end;
  end
  else
    Writeln('No RTL TEncoding is available for this result.');
end;
```

`GetEncoding` returns `False` when the result cannot be resolved by the RTL, including the `ASCII` pseudo code page `0`. `GetEncodingDef` returns the resolved encoding, or your explicit fallback, or `TEncoding.Default` when no fallback is supplied. A caller-supplied fallback remains caller-owned.

## Validation and Documentation
The current suite passes **104/104 tests** on Delphi 12 Win32 and Win64 in each of the four `R+/R-` and `Q+/Q-` combinations. Recognition snapshots match across directive modes within each platform. The bounded-prefix memory regression also fails on the previous byte-buffer implementation, confirming that it protects the resource limit.

Run the complete native matrix:

```powershell
./tests/run-range-matrix.ps1 `
  -Compiler32 'D:\Embarcadero RAD Studio\23.0\bin\dcc32.exe' `
  -Compiler64 'D:\Embarcadero RAD Studio\23.0\bin\dcc64.exe'
```

See [testing and limitations](testing.md), [test workflow](tests/README.md), and [corpus expectations](tests/corpus/README.md). The curated fixtures establish regressions, not accuracy on unseen documents or calibrated probabilities.

## Notes

- Encoding detection must run on the original byte representation of the text. Pass `TBytes`, `TStream`, or a file path. Do not convert unknown text into `string` first, because the original encoding information may already be lost at that point.
- `UTF-8` without BOM can still be conservative for short or ambiguous samples (see [tests](testing.md))
- Statistical decisions remain provisional until `Finish` / `DataEnd`; stream helpers therefore read to EOF unless a BOM or a recognized escape designator provides an early result. A late GB18030 character or malformed Unicode tail can change a prefix guess.
- `Finish` closes the current detection, including an empty or unknown result. Repeated `Finish` is idempotent; call `Reset` before feeding a new input. Disabled code pages remain disabled after `Reset`.
- `Confidence` is a heuristic score, not a calibrated probability of correct detection.
- BOM-less UTF-16 requires plausible text as well as valid code units, while allowing sparse controls in short text. OEM heuristics require diverse signature bytes or repeated in-word accents / multiline graphic layout; isolated Western symbols remain insufficient. These are conservative policies, not complete binary classification or probability calibration.
- Inputs up to 128 bytes retain literal SBCS/Latin-1 evidence. In longer inputs, uniform runs are neutralized in the statistical sample so extreme repetitions do not drown out prose. Original bytes still drive Unicode/CJK syntax checks and OEM/NFO layout evidence. The accented-NFO exception requires aligned top, side and bottom borders, not scattered corner-like letters. Byte-identical inputs with different intended encodings remain inherently ambiguous.
- SBCS mixed words preserve their ASCII-prefix statistics across `Feed` boundaries; ASCII-only words are discarded consistently, including at EOF. Fixed-size model summaries replace prefix byte buffers, keeping pending memory below 1 KiB regardless of word length.
- `GetEncoding` refuses the unusual UCS-4 byte orders 2143 and 3412: their legacy numeric aliases 12000/12001 must not select an ordinary UTF-32 decoder. `GetEncodingDef` still returns the caller's explicit fallback when resolution is unavailable.
- See the [October 2026 detection review](tests/review-2026-10-24/REPORT.ru.md) for fixes, reproducible tests, remaining limitations and research-based development ideas. Supplementary Free Pascal results do not replace the Delphi Win32/Win64 validation matrix.

## License

The repository includes the original license text in [LICENSE](LICENSE).
