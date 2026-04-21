# chsdet
chsdet is a Delphi port of the Mozilla-based charset detector, updated for modern Delphi versions. It detects text encodings from raw bytes, streams, or files and returns a compact result record with the detected charset name, Windows code page, language hint, confidence, and BOM information (see `Supported Charsets` section in this file).

The source code for chsdet is available at: https://sourceforge.net/projects/chsdet/files/. 
The public API (DLL) has not been modified, but modern wrappers have been added to allow direct use of the detector core (see `ChsDet.EncodingDetector.pas` and `ChsDet.Fluent.pas`)

## What Changed
- the detector core was kept byte-oriented with `AnsiChar` and `PAnsiChar` so modern Unicode `Char` semantics do not corrupt the original algorithms
- legacy include paths and RTL references were updated for current Delphi compilers
- The source tree structure has been reorganized, to make it easier (in my opinion) to integrate chsdet into other projects.
- a guard was added to reduce false Unicode positives for single-byte text that contains high-byte characters but no BOM or zero-byte evidence
- DUnitX coverage was added for representative encodings and API entry points
  
## Supported Charsets
The table below is copied from the original [ReadMe.txt](ReadMe.txt) and updated to match the current public detector outputs in this port.
| Code page | Name | Notes |
| ---: | --- | --- |
| 0 | `ASCII` | Pseudo code page used for pure ASCII input. |
| 855 | `IBM855` | DOS Cyrillic. |
| 866 | `IBM866` | DOS Cyrillic. |
| 932 | `Shift_JIS` | Japanese. |
| 950 | `Big5` | Traditional Chinese. |
| 1200 | `UTF-16LE` | Unicode with BOM-aware detection. |
| 1201 | `UTF-16BE` | Unicode with BOM-aware detection. |
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
| 28595 | `ISO-8859-5` | Cyrillic; public output may be paired with Russian or Bulgarian language hints. |
| 28597 | `ISO-8859-7` | Greek. |
| 28598 | `ISO-8859-8` | Hebrew. |
| 50222 | `ISO-2022-JP` | Escape-based Japanese encoding. |
| 50225 | `ISO-2022-KR` | Escape-based Korean encoding. |
| 50227 | `ISO-2022-CN` | Escape-based Chinese encoding. |
| 51932 | `EUC-JP` | Japanese multibyte encoding. |
| 51936 | `x-euc-tw` | Traditional Chinese EUC variant exposed by the detector core. |
| 51949 | `EUC-KR` | Korean multibyte encoding. |
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
    Writeln(Encoding.EncodingName)
  else
    Writeln('No RTL TEncoding is available for this result.');
end;
```


## Notes

- Unknown input should be processed as bytes, streams, or files
- `UTF-8` without BOM can still be conservative for short or ambiguous samples (see [tests](docs/testing.md))
