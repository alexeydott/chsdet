unit ChsDet.Tests;

interface

uses
  DUnitX.TestFramework,
  System.Classes,
  System.IOUtils,
  System.Math,
  System.SysUtils,
  ChsDet.Corpus,
  ChsDet.EncodingDetector,
  ChsDet.Fluent,
  nsCore;

type
  [TestFixture]
  TChsDetectorTests = class
  private
    class function RepeatText(const Value: string; Count: Integer): string; static;
    class function CombineBytes(const Prefix, Payload: TBytes): TBytes; static;
    class function BuildBytes(const Text: string; Encoding: TEncoding; IncludePreamble: Boolean = False): TBytes; static;
    class function MakeTempFile(const Bytes: TBytes): string; static;
    class function LoadCorpusFixtureBytes(const FileName: string): TBytes; static;
    class function AsciiText: string; static;
    class function RussianText: string; static;
    class function Latin1252Text: string; static;
    class function JapaneseText: string; static;
  public
    [Test] procedure DetectsAsciiFromBytes;
    [Test] procedure DetectsUtf8BomFromBytesAndResolvesEncoding;
    [Test] procedure DetectsUtf16LeFromBytes;
    [Test] procedure DetectsUtf16BeFromStreamViaFluentApi;
    [Test] procedure MapsUcs4Bom2143Correctly;
    [Test] procedure MapsUcs4Bom3412Correctly;
    [Test] procedure DetectsWindows1251FromFile;
    [Test] procedure DisableCodePageRemovesAllMatching1251Charsets;
    [Test] procedure DetectsWindows1252FromBytes;
    [Test] procedure DetectsWindows1252WithOnlyEuroC1Bytes;
    [Test] procedure DetectsUtf8WithoutBomFromBytes;
    [Test] procedure PromotesWindows1253WhenC1BytesArePresent;
    [Test] procedure DetectsWindows1253WithoutC1FromDiscriminatorBytes;
    [Test] procedure DetectsIbm866FromChunkedInput;
    [Test] procedure DetectsCp437FromCorpusNfoArt;
    [Test] procedure DetectsCp437FromSmallNfoArt;
    [Test] procedure DoesNotDetectCp437WithoutPseudoGraphicsAsIbm437;
    [Test] procedure DoesNotTreatPlainOemTextAsCp437PseudoGraphics;
    [Test] procedure DetectsIbm850FromCorpus;
    [Test] procedure DetectsIbm852FromCorpus;
    [Test] procedure DetectsIbm858FromCorpus;
    [Test] procedure DetectsWindows1250FromCorpus;
    [Test] procedure DetectsKoi8UFromCorpus;
    [Test] procedure DisableCodePageSuppressesCp437PseudoGraphicsDetection;
    [Test] procedure DisableCodePageSuppressesOemTextSignatureDetection;
    [Test] procedure DisableCodePageSuppressesWindows1250SignatureDetection;
    [Test] procedure DisableCodePageSuppressesKoi8USignatureDetection;
    [Test] procedure DetectsShiftJisFromBytes;
    [Test] procedure DetectsIso88598FromVisualCorpusSample;
    [Test] procedure DetectsBig5FromBytes;
    [Test] procedure DetectsEucJpFromBytes;
    [Test] procedure DetectsGb18030FromChunkedInput;
    [Test] procedure DetectsIso2022JpFromFile;
    [Test] procedure UnrelatedDisableDoesNotBreakIso2022Detection;
    [Test] procedure DetectsEucKrFromFile;
    [Test] procedure DetectsIso2022KrFromBytes;
    [Test] procedure DetectsIso2022CnAcrossChunkBoundaries;
    [Test] procedure DisableCodePageSuppressesIso2022CnDetection;
    [Test] procedure DetectsHzGb2312FromBytes;
    [Test] procedure CjkCorpusFixturesDoNotLookLikeCp437PseudoGraphics;
    [Test] procedure CorpusStrictBenchmarkPasses;
    [Test] procedure GetEncodingDefUsesFallbacks;
  end;

implementation

{ TChsDetectorTests }

class function TChsDetectorTests.RepeatText(const Value: string; Count: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Count do
    Result := Result + Value;
end;

class function TChsDetectorTests.CombineBytes(const Prefix, Payload: TBytes): TBytes;
var
  PrefixLen: Integer;
  PayloadLen: Integer;
begin
  PrefixLen := Length(Prefix);
  PayloadLen := Length(Payload);
  SetLength(Result, PrefixLen + PayloadLen);

  if PrefixLen > 0 then
    Move(Prefix[0], Result[0], PrefixLen);

  if PayloadLen > 0 then
    Move(Payload[0], Result[PrefixLen], PayloadLen);
end;

class function TChsDetectorTests.BuildBytes(const Text: string; Encoding: TEncoding; IncludePreamble: Boolean): TBytes;
var
  Preamble: TBytes;
  Payload: TBytes;
begin
  Payload := Encoding.GetBytes(Text);
  if IncludePreamble then
    Preamble := Encoding.GetPreamble
  else
    SetLength(Preamble, 0);

  Result := CombineBytes(Preamble, Payload);
end;

class function TChsDetectorTests.MakeTempFile(const Bytes: TBytes): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName + '.txt');
  TFile.WriteAllBytes(Result, Bytes);
end;

class function TChsDetectorTests.LoadCorpusFixtureBytes(const FileName: string): TBytes;
begin
  Result := TFile.ReadAllBytes(TPath.Combine(TChsCorpus.DataDir, FileName));
end;

class function TChsDetectorTests.AsciiText: string;
begin
  Result := RepeatText('Plain ASCII detector sample. ', 100);
end;

class function TChsDetectorTests.RussianText: string;
const
  Phrase =
    #$042D#$0442#$043E#$0020#$0442#$0435#$0441#$0442#$0020#$043A#$043E#$0434#$0438#$0440#$043E#$0432#$043A#$0438#$002E#$0020;
begin
  Result := RepeatText(Phrase, 120);
end;

class function TChsDetectorTests.Latin1252Text: string;
const
  Phrase =
    #$0043#$0061#$0066#$00E9#$0020#$0063#$0072#$00E8#$006D#$0065#$0020#$0064#$00E9#$006A#$00E0#$0020#$0076#$0075#$002E#$0020 +
    #$00C0#$0020#$006C#$0061#$0020#$0063#$0061#$0072#$0074#$0065#$002C#$0020#$00E9#$006C#$00E8#$0076#$0065#$002C#$0020 +
    #$0066#$0069#$0061#$006E#$0063#$00E9#$002C#$0020#$0067#$0061#$0072#$00E7#$006F#$006E#$002C#$0020#$004E#$006F#$00EB#$006C#$002C#$0020#$00FC#$0062#$0065#$0072#$002E#$0020;
begin
  Result := RepeatText(Phrase, 80);
end;

class function TChsDetectorTests.JapaneseText: string;
const
  Phrase =
    #$3053#$308C#$306F#$6587#$5B57#$30B3#$30FC#$30C9#$5224#$5B9A#$306E#$30C6#$30B9#$30C8#$3067#$3059#$3002 +
    #$65E5#$672C#$8A9E#$306E#$6587#$7AE0#$3092#$7E70#$308A#$8FD4#$3057#$307E#$3059#$3002;
begin
  Result := RepeatText(Phrase, 100);
end;

procedure TChsDetectorTests.DetectsAsciiFromBytes;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
  Encoding: TEncoding;
begin
  Bytes := TEncoding.ASCII.GetBytes(AsciiText);
  Detection := TChsEncodingDetector.Detect(Bytes);

  Assert.AreEqual<Integer>(0, Detection.CodePage);
  Assert.AreEqual('ASCII', Detection.Name);
  Assert.IsFalse(Detection.HasBom);
  Assert.IsFalse(Detection.GetEncoding(Encoding));
  Assert.IsNull(Encoding);
end;

procedure TChsDetectorTests.DetectsUtf8BomFromBytesAndResolvesEncoding;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
  Encoding: TEncoding;
begin
  Bytes := BuildBytes(RussianText, TEncoding.UTF8, True);
  Detection := TChsEncodingDetector.Detect(Bytes);

  Assert.AreEqual<Integer>(65001, Detection.CodePage);
  Assert.AreEqual('UTF-8', Detection.Name);
  Assert.AreEqual<Integer>(Ord(BOM_UTF8), Ord(Detection.BomKind));
  Assert.IsTrue(Detection.GetEncoding(Encoding));
  Assert.AreEqual<Integer>(65001, Encoding.CodePage);
end;

procedure TChsDetectorTests.DetectsUtf16LeFromBytes;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := BuildBytes(RussianText, TEncoding.Unicode, True);
  Detection := TChsEncodingDetector.Detect(Bytes);

  Assert.AreEqual<Integer>(1200, Detection.CodePage);
  Assert.AreEqual('UTF-16LE', Detection.Name);
  Assert.AreEqual<Integer>(Ord(BOM_UTF16_LE), Ord(Detection.BomKind));
  Assert.IsTrue(Detection.HasBom);
end;

procedure TChsDetectorTests.DetectsUtf16BeFromStreamViaFluentApi;
var
  Bytes: TBytes;
  Stream: TBytesStream;
  Detection: TChsDetectionResult;
begin
  Bytes := BuildBytes(RussianText, TEncoding.BigEndianUnicode, True);
  Stream := TBytesStream.Create(Bytes);
  try
    Detection := TChsDetect.From(Stream, 257).Detect;
  finally
    Stream.Free;
  end;

  Assert.AreEqual<Integer>(1201, Detection.CodePage);
  Assert.AreEqual('UTF-16BE', Detection.Name);
  Assert.AreEqual<Integer>(Ord(BOM_UTF16_BE), Ord(Detection.BomKind));
end;

procedure TChsDetectorTests.MapsUcs4Bom2143Correctly;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := TBytes.Create($00, $00, $FF, $FE, $00, $00, $00, $41);
  Detection := TChsEncodingDetector.Detect(Bytes);

  Assert.AreEqual<Integer>(12000, Detection.CodePage);
  Assert.AreEqual('X-ISO-10646-UCS-4-2143', Detection.Name);
  Assert.AreEqual<Integer>(Ord(BOM_UCS4_2143), Ord(Detection.BomKind));
end;

procedure TChsDetectorTests.MapsUcs4Bom3412Correctly;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := TBytes.Create($FE, $FF, $00, $00, $00, $00, $41, $00);
  Detection := TChsEncodingDetector.Detect(Bytes);

  Assert.AreEqual<Integer>(12001, Detection.CodePage);
  Assert.AreEqual('X-ISO-10646-UCS-4-3412', Detection.Name);
  Assert.AreEqual<Integer>(Ord(BOM_UCS4_3412), Ord(Detection.BomKind));
end;

procedure TChsDetectorTests.DetectsWindows1251FromFile;
var
  Bytes: TBytes;
  FileName: string;
  Detection: TChsDetectionResult;
begin
  Bytes := BuildBytes(RussianText, TEncoding.GetEncoding(1251));
  FileName := MakeTempFile(Bytes);
  try
    Detection := TChsDetect.DetectFile(FileName);
  finally
    TFile.Delete(FileName);
  end;

  Assert.AreEqual<Integer>(1251, Detection.CodePage);
  Assert.AreEqual('windows-1251', Detection.Name);
  Assert.AreEqual('russian', Detection.Language);
end;

procedure TChsDetectorTests.DisableCodePageRemovesAllMatching1251Charsets;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := BuildBytes(RussianText, TEncoding.GetEncoding(1251));
  Detection := TChsDetect.New
    .DisableCodePage(1251)
    .Feed(Bytes)
    .Detect;

  Assert.AreNotEqual<Integer>(1251, Detection.CodePage);
end;

procedure TChsDetectorTests.DetectsWindows1252FromBytes;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := BuildBytes(Latin1252Text, TEncoding.GetEncoding(1252));
  Detection := TChsEncodingDetector.Detect(Bytes);

  Assert.AreEqual<Integer>(1252, Detection.CodePage);
  Assert.AreEqual('windows-1252', Detection.Name);
  Assert.IsTrue(Detection.Confidence >= 0.20, 'Confidence must stay above the reporting threshold.');
end;

procedure TChsDetectorTests.DetectsWindows1252WithOnlyEuroC1Bytes;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := BuildBytes(RepeatText('Price 10 ' + #$20AC + '. ', 180), TEncoding.GetEncoding(1252));
  Detection := TChsEncodingDetector.Detect(Bytes);

  Assert.AreEqual<Integer>(1252, Detection.CodePage);
  Assert.AreEqual('windows-1252', Detection.Name);
end;

procedure TChsDetectorTests.DetectsUtf8WithoutBomFromBytes;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := TEncoding.UTF8.GetBytes(RepeatText(
    #$042D#$0442#$043E#$0020#$0074#$0065#$0073#$0074#$0020#$0055#$0054#$0046#$002D#$0038#$0020#$0431#$0435#$0437#$0020#$0042#$004F#$004D#$002E#$0020,
    180));
  Detection := TChsEncodingDetector.Detect(Bytes);

  Assert.AreEqual<Integer>(65001, Detection.CodePage);
  Assert.AreEqual('UTF-8', Detection.Name);
  Assert.IsFalse(Detection.HasBom);
end;

procedure TChsDetectorTests.PromotesWindows1253WhenC1BytesArePresent;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := BuildBytes(
    RepeatText(
      #$0391#$03C5#$03C4#$03BF#$0020#$03B5#$03B9#$03BD#$03B1#$03B9#$0020#$03B4#$03BF#$03BA#$03B9#$03BC#$03B7#$0020#$03BC#$03B5#$0020#$20AC#$0020 +
      #$03BA#$03B1#$03B9#$0020#$03B5#$03B9#$03C3#$03B1#$03B3#$03C9#$03B3#$03B9#$03BA#$03B1#$002E#$0020,
      160),
    TEncoding.GetEncoding(1253));
  Detection := TChsEncodingDetector.Detect(Bytes);

  Assert.AreEqual<Integer>(1253, Detection.CodePage);
  Assert.AreEqual('windows-1253', Detection.Name);
end;

procedure TChsDetectorTests.DetectsWindows1253WithoutC1FromDiscriminatorBytes;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('windows-1253-no-c1.txt');
  Detection := TChsEncodingDetector.Detect(Bytes);

  Assert.AreEqual<Integer>(1253, Detection.CodePage);
  Assert.AreEqual('windows-1253', Detection.Name);
  Assert.AreEqual('greek', Detection.Language);
end;

procedure TChsDetectorTests.DetectsIbm866FromChunkedInput;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
  Detector: IChsFluentDetector;
  Offset: Integer;
  Count: Integer;
const
  ChunkSize = 37;
begin
  Bytes := BuildBytes(RussianText, TEncoding.GetEncoding(866));
  Detector := TChsDetect.New;
  Offset := 0;

  while Offset < Length(Bytes) do
  begin
    Count := Min(ChunkSize, Length(Bytes) - Offset);
    Detector.Feed(Bytes, Offset, Count);
    Inc(Offset, Count);
  end;

  Detection := Detector.Detect;

  Assert.AreEqual<Integer>(866, Detection.CodePage);
  Assert.AreEqual('IBM866', Detection.Name);
end;

procedure TChsDetectorTests.DetectsCp437FromCorpusNfoArt;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('cp437-nfo-art.txt');
  Detection := TChsDetect.Detect(Bytes);

  Assert.AreEqual<Integer>(437, Detection.CodePage);
  Assert.AreEqual('IBM437', Detection.Name);
  Assert.AreEqual('DOS', Detection.Language);
end;

procedure TChsDetectorTests.DetectsCp437FromSmallNfoArt;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('cp437-small-nfo-art.txt');
  Detection := TChsDetect.Detect(Bytes);

  Assert.AreEqual<Integer>(437, Detection.CodePage);
  Assert.AreEqual('IBM437', Detection.Name);
  Assert.AreEqual('DOS', Detection.Language);
end;

procedure TChsDetectorTests.DoesNotDetectCp437WithoutPseudoGraphicsAsIbm437;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('cp437-plain-no-art.txt');
  Detection := TChsDetect.Detect(Bytes);

  Assert.AreNotEqual<Integer>(437, Detection.CodePage);
  Assert.AreNotEqual('IBM437', Detection.Name);
end;

procedure TChsDetectorTests.DoesNotTreatPlainOemTextAsCp437PseudoGraphics;
const
  PlainOemFixtures: array [0..2] of string = (
    'ibm850-plain-no-art.txt',
    'ibm852-plain-no-art.txt',
    'ibm858-plain-no-art.txt'
  );
var
  FileName: string;
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  for FileName in PlainOemFixtures do
  begin
    Bytes := LoadCorpusFixtureBytes(FileName);
    Detection := TChsDetect.Detect(Bytes);

    Assert.AreNotEqual<Integer>(437, Detection.CodePage, FileName);
    Assert.AreNotEqual('IBM437', Detection.Name, FileName);
  end;
end;

procedure TChsDetectorTests.DetectsIbm850FromCorpus;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('ibm850.txt');
  Detection := TChsDetect.Detect(Bytes);

  Assert.AreEqual<Integer>(850, Detection.CodePage);
  Assert.AreEqual('IBM850', Detection.Name);
  Assert.AreEqual('DOS', Detection.Language);
end;

procedure TChsDetectorTests.DetectsIbm852FromCorpus;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('ibm852.txt');
  Detection := TChsDetect.Detect(Bytes);

  Assert.AreEqual<Integer>(852, Detection.CodePage);
  Assert.AreEqual('IBM852', Detection.Name);
  Assert.AreEqual('DOS', Detection.Language);
end;

procedure TChsDetectorTests.DetectsIbm858FromCorpus;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('ibm858.txt');
  Detection := TChsDetect.Detect(Bytes);

  Assert.AreEqual<Integer>(858, Detection.CodePage);
  Assert.AreEqual('IBM858', Detection.Name);
  Assert.AreEqual('DOS', Detection.Language);
end;

procedure TChsDetectorTests.DetectsWindows1250FromCorpus;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('windows-1250.txt');
  Detection := TChsDetect.Detect(Bytes);

  Assert.AreEqual<Integer>(1250, Detection.CodePage);
  Assert.AreEqual('windows-1250', Detection.Name);
  Assert.AreEqual('central european', Detection.Language);
end;

procedure TChsDetectorTests.DetectsKoi8UFromCorpus;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('koi8-u.txt');
  Detection := TChsDetect.Detect(Bytes);

  Assert.AreEqual<Integer>(21866, Detection.CodePage);
  Assert.AreEqual('KOI8-U', Detection.Name);
  Assert.AreEqual('ukrainian', Detection.Language);
end;

procedure TChsDetectorTests.DisableCodePageSuppressesCp437PseudoGraphicsDetection;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('cp437-nfo-art.txt');
  Detection := TChsDetect.New
    .DisableCodePage(437)
    .Feed(Bytes)
    .Detect;

  Assert.AreNotEqual<Integer>(437, Detection.CodePage);
  Assert.AreNotEqual('IBM437', Detection.Name);
end;

procedure TChsDetectorTests.DisableCodePageSuppressesOemTextSignatureDetection;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('ibm850.txt');
  Detection := TChsDetect.New
    .DisableCodePage(850)
    .Feed(Bytes)
    .Detect;

  Assert.AreNotEqual<Integer>(850, Detection.CodePage);
  Assert.AreNotEqual('IBM850', Detection.Name);
end;

procedure TChsDetectorTests.DisableCodePageSuppressesWindows1250SignatureDetection;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('windows-1250.txt');
  Detection := TChsDetect.New
    .DisableCodePage(1250)
    .Feed(Bytes)
    .Detect;

  Assert.AreNotEqual<Integer>(1250, Detection.CodePage);
  Assert.AreNotEqual('windows-1250', Detection.Name);
end;

procedure TChsDetectorTests.DisableCodePageSuppressesKoi8USignatureDetection;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('koi8-u.txt');
  Detection := TChsDetect.New
    .DisableCodePage(21866)
    .Feed(Bytes)
    .Detect;

  Assert.AreNotEqual<Integer>(21866, Detection.CodePage);
  Assert.AreNotEqual('KOI8-U', Detection.Name);
end;

procedure TChsDetectorTests.DetectsShiftJisFromBytes;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := BuildBytes(JapaneseText, TEncoding.GetEncoding(932));
  Detection := TChsDetect.Detect(Bytes);

  Assert.AreEqual<Integer>(932, Detection.CodePage);
  Assert.AreEqual('Shift_JIS', Detection.Name);
  Assert.AreEqual('japanese', Detection.Language);
end;

procedure TChsDetectorTests.DetectsIso88598FromVisualCorpusSample;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('iso-8859-8.txt');
  Detection := TChsDetect.Detect(Bytes);

  Assert.AreEqual<Integer>(28598, Detection.CodePage);
  Assert.AreEqual('ISO-8859-8', Detection.Name);
  Assert.AreEqual('hebrew', Detection.Language);
end;

procedure TChsDetectorTests.DetectsBig5FromBytes;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('big5.txt');
  Detection := TChsDetect.Detect(Bytes);

  Assert.AreEqual<Integer>(950, Detection.CodePage);
  Assert.AreEqual('Big5', Detection.Name);
  Assert.AreEqual('ch', Detection.Language);
end;

procedure TChsDetectorTests.DetectsEucJpFromBytes;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('euc-jp.txt');
  Detection := TChsDetect.Detect(Bytes);

  Assert.AreEqual<Integer>(51932, Detection.CodePage);
  Assert.AreEqual('EUC-JP', Detection.Name);
  Assert.AreEqual('japanese', Detection.Language);
end;

procedure TChsDetectorTests.DetectsGb18030FromChunkedInput;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
  Detector: IChsFluentDetector;
  Offset: Integer;
  Count: Integer;
const
  ChunkSize = 53;
begin
  Bytes := LoadCorpusFixtureBytes('gb18030.txt');
  Detector := TChsDetect.New;
  Offset := 0;

  while Offset < Length(Bytes) do
  begin
    Count := Min(ChunkSize, Length(Bytes) - Offset);
    Detector.Feed(Bytes, Offset, Count);
    Inc(Offset, Count);
  end;

  Detection := Detector.Detect;

  Assert.AreEqual<Integer>(54936, Detection.CodePage);
  Assert.AreEqual('GB18030', Detection.Name);
  Assert.AreEqual('ch', Detection.Language);
end;

procedure TChsDetectorTests.DetectsIso2022JpFromFile;
var
  FileName: string;
  Detection: TChsDetectionResult;
begin
  FileName := TPath.Combine(TChsCorpus.DataDir, 'iso-2022-jp.txt');
  Detection := TChsEncodingDetector.DetectFile(FileName);

  Assert.AreEqual<Integer>(50222, Detection.CodePage);
  Assert.AreEqual('ISO-2022-JP', Detection.Name);
  Assert.AreEqual('japanese', Detection.Language);
end;

procedure TChsDetectorTests.UnrelatedDisableDoesNotBreakIso2022Detection;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('iso-2022-jp.txt');
  Detection := TChsDetect.New
    .DisableCodePage(1252)
    .Feed(Bytes)
    .Detect;

  Assert.AreEqual<Integer>(50222, Detection.CodePage);
  Assert.AreEqual('ISO-2022-JP', Detection.Name);
end;

procedure TChsDetectorTests.DetectsEucKrFromFile;
var
  FileName: string;
  Detection: TChsDetectionResult;
begin
  FileName := TPath.Combine(TChsCorpus.DataDir, 'euc-kr.txt');
  Detection := TChsDetect.DetectFile(FileName);

  Assert.AreEqual<Integer>(51949, Detection.CodePage);
  Assert.AreEqual('EUC-KR', Detection.Name);
  Assert.AreEqual('kr', Detection.Language);
end;

procedure TChsDetectorTests.DetectsIso2022KrFromBytes;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('iso-2022-kr.txt');
  Detection := TChsEncodingDetector.Detect(Bytes);

  Assert.AreEqual<Integer>(50225, Detection.CodePage);
  Assert.AreEqual('ISO-2022-KR', Detection.Name);
  Assert.AreEqual('kr', Detection.Language);
end;

procedure TChsDetectorTests.DetectsIso2022CnAcrossChunkBoundaries;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
  Detector: IChsFluentDetector;
  Offset: Integer;
  Count: Integer;
const
  ChunkSize = 2;
begin
  Bytes := LoadCorpusFixtureBytes('iso-2022-cn.txt');
  Detector := TChsDetect.New;
  Offset := 0;

  while Offset < Length(Bytes) do
  begin
    Count := Min(ChunkSize, Length(Bytes) - Offset);
    Detector.Feed(Bytes, Offset, Count);
    Inc(Offset, Count);
  end;

  Detection := Detector.Detect;

  Assert.AreEqual<Integer>(50227, Detection.CodePage);
  Assert.AreEqual('ISO-2022-CN', Detection.Name);
  Assert.AreEqual('ch', Detection.Language);
end;

procedure TChsDetectorTests.DisableCodePageSuppressesIso2022CnDetection;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('iso-2022-cn.txt');
  Detection := TChsDetect.New
    .DisableCodePage(50227)
    .Feed(Bytes)
    .Detect;

  Assert.AreNotEqual<Integer>(50227, Detection.CodePage);
end;

procedure TChsDetectorTests.DetectsHzGb2312FromBytes;
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Bytes := LoadCorpusFixtureBytes('hz-gb-2312.txt');
  Detection := TChsEncodingDetector.Detect(Bytes);

  Assert.AreEqual<Integer>(52936, Detection.CodePage);
  Assert.AreEqual('HZ-GB-2312', Detection.Name);
  Assert.AreEqual('ch', Detection.Language);
end;

procedure TChsDetectorTests.CjkCorpusFixturesDoNotLookLikeCp437PseudoGraphics;
const
  CjkFixtures: array [0..3] of string = (
    'big5.txt',
    'euc-jp.txt',
    'euc-kr.txt',
    'gb18030.txt'
  );
var
  FileName: string;
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  for FileName in CjkFixtures do
  begin
    Bytes := LoadCorpusFixtureBytes(FileName);
    Detection := TChsDetect.Detect(Bytes);

    Assert.AreNotEqual<Integer>(437, Detection.CodePage, FileName);
    Assert.AreNotEqual('IBM437', Detection.Name, FileName);
  end;
end;

procedure TChsDetectorTests.CorpusStrictBenchmarkPasses;
var
  Results: TArray<TChsCorpusResult>;
  Item: TChsCorpusResult;
  Failures: TStringList;
begin
  Results := TChsCorpus.RunAll;
  Failures := TStringList.Create;
  try
    for Item in Results do
      if (Item.CaseInfo.Tier = ctStrict) and (not Item.IsExactMatch) then
        Failures.Add(Format(
          '%s: expected %s/%d, got %s/%d',
          [Item.CaseInfo.FileName,
           Item.CaseInfo.ExpectedName,
           Item.CaseInfo.ExpectedCodePage,
           Item.Detection.Name,
           Item.Detection.CodePage]));

    Assert.AreEqual(0, Failures.Count, Failures.Text);
  finally
    Failures.Free;
  end;
end;

procedure TChsDetectorTests.GetEncodingDefUsesFallbacks;
var
  Detection: TChsDetectionResult;
  DefaultEncoding: TEncoding;
  ResolvedEncoding: TEncoding;
begin
  Detection := TChsEncodingDetector.Detect(TEncoding.ASCII.GetBytes(AsciiText));
  DefaultEncoding := TEncoding.UTF8;

  ResolvedEncoding := Detection.GetEncodingDef(DefaultEncoding);
  Assert.AreEqual<Integer>(DefaultEncoding.CodePage, ResolvedEncoding.CodePage);

  ResolvedEncoding := Detection.GetEncodingDef;
  Assert.AreEqual<Integer>(TEncoding.Default.CodePage, ResolvedEncoding.CodePage);
end;

initialization
  TDUnitX.RegisterTestFixture(TChsDetectorTests);

end.
