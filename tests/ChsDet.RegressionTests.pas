unit ChsDet.RegressionTests;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.IOUtils, nsCore,
  ChsDet.Corpus, ChsDet.EncodingDetector;

type
  [TestFixture]
  TChsRegressionTests = class
  private
    class function Utf16AsciiBytes(BigEndian: Boolean): TBytes; static;
    class function Append(const Bytes: TBytes; const Tail: array of Byte): TBytes; static;
    class function DetectChunks(const Bytes: TBytes; Chunk: Integer): TChsDetectionResult; static;
  public
    [Test] procedure Utf16AsciiWithoutBomAtEverySplit;
    [Test] procedure Utf16WithoutBomRejectsMalformedTail;
    [Test] procedure Utf16SurrogatePairSurvivesEveryTailSplit;
    [Test] procedure NonBreakingSpaceIsNotAscii;
    [Test] procedure DisabledAsciiStaysDisabledAfterReset;
    [Test] procedure FeedRejectsOverflowingRangeWithoutChangingState;
    [Test] procedure UnusualUcs4ByteOrdersDoNotResolveToUtf32;
    [Test] procedure EucTwUsesTraditionalChineseCodePage;
    [Test] procedure Gb18030TailCanRefineACompleteGbkPrefix;
    [Test] procedure DisabledGbkKeepsTheCompatibleGb18030Candidate;
    [Test] procedure FinishIsTerminalAndResetStartsANewDetection;
    [Test] procedure WholeFeedPreservesTheAsciiPrefixOfAMixedWord;
    [Test] procedure BomlessUtf16RejectsControlDominatedBinary;
    [Test] procedure RepeatedWesternSymbolsDoNotSelectOemFamilies;
    [Test] procedure BomlessUtf16TextControlsRemainSupported;
  end;

implementation

procedure TChsRegressionTests.BomlessUtf16TextControlsRemainSupported;
const
  Chunks: array [0..3] of Integer = (1, 3, 64, 8192);
var
  Data: TBytes;
  Endian, Chunk: Integer;
begin
  for Endian := 0 to 1 do
  begin
    Data := Utf16AsciiBytes(Endian = 1);
    // Text whitespace, Unicode NEL, and one isolated terminal escape are not
    // a control-dominated binary payload. Include both byte orders without BOM.
    if Endian = 0 then
      Data := Append(Data, [$09, 0, $0A, 0, $0B, 0, $0C, 0, $0D, 0, $85, 0, $1B, 0])
    else
      Data := Append(Data, [0, $09, 0, $0A, 0, $0B, 0, $0C, 0, $0D, 0, $85, 0, $1B]);
    for Chunk in Chunks do
      Assert.AreEqual<Integer>(1200 + Endian, DetectChunks(Data, Chunk).CodePage,
        Format('Text controls must remain supported: endian=%d chunk=%d', [Endian, Chunk]));
  end;
end;

procedure TChsRegressionTests.BomlessUtf16RejectsControlDominatedBinary;
const
  Chunks: array [0..3] of Integer = (1, 3, 64, 8192);
var
  Data: TBytes;
  Endian, Kind, I, Chunk: Integer;
  Actual: TChsDetectionResult;
begin
  SetLength(Data, 256);
  for Endian := 0 to 1 do
    for Kind := 0 to 1 do
    begin
      for I := 0 to 127 do
      begin
        Data[I * 2 + Endian] := 0;
        if Kind = 0 then
          Data[I * 2 + 1 - Endian] := Byte(1 + I mod 4)
        else
          Data[I * 2 + 1 - Endian] := $80;
      end;
      for Chunk in Chunks do
      begin
        Actual := DetectChunks(Data, Chunk);
        Assert.IsTrue((Actual.CodePage <> 1200) and (Actual.CodePage <> 1201),
          Format('Small integer/control array is not text: endian=%d kind=%d chunk=%d',
            [Endian, Kind, Chunk]));
      end;
    end;
end;

procedure TChsRegressionTests.RepeatedWesternSymbolsDoNotSelectOemFamilies;
const
  Symbols: array [0..2] of Byte = ($87, $A0, $B0);
  Chunks: array [0..3] of Integer = (1, 3, 64, 8192);
var
  Data: TBytes;
  Symbol: Byte;
  I, Chunk: Integer;
  Actual: TChsDetectionResult;
begin
  SetLength(Data, 384);
  for Symbol in Symbols do
  begin
    // CP1252 dagger, nonbreaking space or degree sign among ASCII labels.
    for I := 0 to 127 do
    begin
      Data[I * 3] := Ord('x');
      Data[I * 3 + 1] := Symbol;
      Data[I * 3 + 2] := Ord(' ');
    end;
    for Chunk in Chunks do
    begin
      Actual := DetectChunks(Data, Chunk);
      Assert.IsTrue((Actual.CodePage <> 437) and (Actual.CodePage <> 850) and
        (Actual.CodePage <> 852) and (Actual.CodePage <> 858),
        Format('Repeated CP1252 symbol %.2x must not accumulate OEM certainty: chunk=%d',
          [Symbol, Chunk]));
    end;
  end;
end;

class function TChsRegressionTests.Utf16AsciiBytes(BigEndian: Boolean): TBytes;
const
  // Independent byte construction: every ASCII code point is one 16-bit unit.
  Text: AnsiString = 'Route 12. North station - South station. Arrival 08:30. '#13#10;
var
  I, J, Offset: Integer;
begin
  // Delphi may reuse a same-length result array from the previous endian case.
  Result := nil;
  SetLength(Result, Length(Text) * 6);
  Offset := 0;
  if BigEndian then
    Offset := 1;
  for J := 0 to 2 do
    for I := 1 to Length(Text) do
      Result[(J * Length(Text) + I - 1) * 2 + Offset] := Byte(Text[I]);
end;

class function TChsRegressionTests.Append(const Bytes: TBytes;
  const Tail: array of Byte): TBytes;
var
  I: Integer;
begin
  Result := Copy(Bytes);
  SetLength(Result, Length(Bytes) + Length(Tail));
  for I := 0 to High(Tail) do
    Result[Length(Bytes) + I] := Tail[I];
end;

class function TChsRegressionTests.DetectChunks(const Bytes: TBytes;
  Chunk: Integer): TChsDetectionResult;
var
  Detector: IChsEncodingDetector;
  Offset, Count: Integer;
begin
  Detector := TChsEncodingDetector.New;
  Offset := 0;
  while Offset < Length(Bytes) do
  begin
    Count := Length(Bytes) - Offset;
    if (Chunk > 0) and (Count > Chunk) then
      Count := Chunk;
    Detector.Feed(Bytes, Offset, Count);
    Inc(Offset, Count);
  end;
  Result := Detector.Finish;
end;

procedure TChsRegressionTests.Utf16AsciiWithoutBomAtEverySplit;
var
  Endian, Split: Integer;
  Bytes: TBytes;
  Detector: IChsEncodingDetector;
  Actual: TChsDetectionResult;
begin
  for Endian := 0 to 1 do
  begin
    Bytes := Utf16AsciiBytes(Endian = 1);
    Detector := TChsEncodingDetector.New;
    for Split := 0 to Length(Bytes) do
    begin
      Detector.Reset;
      Detector.Feed(Bytes, 0, Split);
      Detector.Feed(Bytes, Split, Length(Bytes) - Split);
      Actual := Detector.Finish;
      Assert.AreEqual<Integer>(1200 + Endian, Actual.CodePage,
        Format('Endian %d split %d', [Endian, Split]));
      Assert.AreEqual<Integer>(Ord(BOM_Not_Found), Ord(Actual.BomKind));
    end;
    Actual := DetectChunks(Bytes, 1);
    Assert.AreEqual<Integer>(1200 + Endian, Actual.CodePage);
  end;
end;

procedure TChsRegressionTests.Utf16WithoutBomRejectsMalformedTail;
var
  Endian, Variant, Chunk: Integer;
  Bytes, Base: TBytes;
  Actual: TChsDetectionResult;
begin
  for Endian := 0 to 1 do
  begin
    Base := Utf16AsciiBytes(Endian = 1);
    for Variant := 0 to 3 do
    begin
      case Variant of
        0: Bytes := Append(Base, [$41]); // Incomplete 16-bit code unit.
        1: if Endian = 0 then Bytes := Append(Base, [$00, $D8])
           else Bytes := Append(Base, [$D8, $00]); // Unpaired high surrogate.
        2: if Endian = 0 then Bytes := Append(Base, [$00, $DC])
           else Bytes := Append(Base, [$DC, $00]); // Unpaired low surrogate.
      else
        if Endian = 0 then Bytes := Append(Base, [$00, $D8, $41, $00])
        else Bytes := Append(Base, [$D8, $00, $00, $41]);
      end;
      for Chunk := 0 to 3 do
      begin
        Actual := DetectChunks(Bytes, Chunk);
        // Invalid UTF-16 may still be a valid legacy encoding.
        Assert.AreNotEqual<Integer>(1200 + Endian, Actual.CodePage,
          Format('Endian %d malformed tail %d chunk %d', [Endian, Variant, Chunk]));
      end;
    end;
  end;
end;

procedure TChsRegressionTests.Utf16SurrogatePairSurvivesEveryTailSplit;
var
  Endian, Split: Integer;
  Base, Tail: TBytes;
  Detector: IChsEncodingDetector;
  Actual: TChsDetectionResult;
begin
  for Endian := 0 to 1 do
  begin
    Base := Utf16AsciiBytes(Endian = 1);
    // U+1F680 is D83D DE80 in UTF-16 (Unicode Standard, section 3.9).
    if Endian = 0 then Tail := TBytes.Create($3D, $D8, $80, $DE)
    else Tail := TBytes.Create($D8, $3D, $DE, $80);
    for Split := 0 to Length(Tail) do
    begin
      Detector := TChsEncodingDetector.New;
      Detector.Feed(Base);
      Assert.IsFalse(Detector.IsDone, 'A statistical UTF-16 prefix is provisional');
      Detector.Feed(Tail, 0, Split);
      Detector.Feed(Tail, Split, Length(Tail) - Split);
      Actual := Detector.Finish;
      Assert.AreEqual<Integer>(1200 + Endian, Actual.CodePage);
    end;
  end;
end;

procedure TChsRegressionTests.NonBreakingSpaceIsNotAscii;
var
  Bytes: TBytes;
  Actual: TChsDetectionResult;
  Chunk: Integer;
begin
  // A0 is not a 7-bit ASCII code; no platform code-page encoder is involved.
  Bytes := TBytes.Create($4E, $6F, $72, $74, $68, $A0, $73, $74, $61,
    $74, $69, $6F, $6E, $20, $31, $32, $2E, $0D, $0A);
  for Chunk := 0 to 3 do
  begin
    Actual := DetectChunks(Bytes, Chunk);
    Assert.AreNotEqual<Integer>(0, Actual.CodePage);
    Assert.AreNotEqual('ASCII', Actual.Name);
  end;
end;

procedure TChsRegressionTests.DisabledAsciiStaysDisabledAfterReset;
var
  Detector: IChsEncodingDetector;
  Actual: TChsDetectionResult;
  I: Integer;
begin
  Detector := TChsEncodingDetector.New;
  Detector.DisableCodePage(0);
  for I := 0 to 1 do
  begin
    Detector.Reset;
    Detector.Feed(TBytes.Create($74, $65, $73, $74));
    Actual := Detector.Finish;
    Assert.IsTrue(Actual.IsUnknown, 'Disabled ASCII must not bypass reporting');
    Assert.AreEqual<Double>(0.0, Actual.Confidence);
  end;
end;

procedure TChsRegressionTests.FeedRejectsOverflowingRangeWithoutChangingState;
var
  Bytes: TBytes;
  Detector: IChsEncodingDetector;
  Rejected: Boolean;
  Actual: TChsDetectionResult;
begin
  Bytes := TBytes.Create($74, $65, $73, $74);
  Detector := TChsEncodingDetector.New;
  Rejected := False;
  try
    Detector.Feed(Bytes, 1, MaxInt);
  except
    on E: EArgumentOutOfRangeException do
      Rejected := True;
  end;
  Assert.IsTrue(Rejected, 'The public argument error must be raised before any read');
  Detector.Feed(Bytes);
  Actual := Detector.Finish;
  Assert.AreEqual<Integer>(0, Actual.CodePage, 'A rejected Feed must not change state');
  Assert.AreEqual('ASCII', Actual.Name);
end;

procedure TChsRegressionTests.UnusualUcs4ByteOrdersDoNotResolveToUtf32;
var
  Detection: TChsDetectionResult;
  Encoding: TEncoding;
  Bytes: TBytes;
  I: Integer;
  Resolved: Boolean;
begin
  for I := 0 to 1 do
  begin
    // BOMs from XML 1.0, appendix F.1; the payload is U+0041 in that byte order.
    if I = 0 then Bytes := TBytes.Create($00, $00, $FF, $FE, $00, $00, $41, $00)
    else Bytes := TBytes.Create($FE, $FF, $00, $00, $00, $41, $00, $00);
    Detection := TChsEncodingDetector.Detect(Bytes);
    Assert.AreEqual<Integer>(12000 + I, Detection.CodePage);
    Encoding := nil;
    Resolved := Detection.GetEncoding(Encoding);
    try
      Assert.IsFalse(Resolved, 'UCS-4 2143/3412 is not ordinary UTF-32 LE/BE');
      Assert.IsNull(Encoding);
    finally
      if (Encoding <> nil) and not TEncoding.IsStandardEncoding(Encoding) then
        Encoding.Free;
    end;
  end;
end;

procedure TChsRegressionTests.EucTwUsesTraditionalChineseCodePage;
begin
  // Microsoft Code Page Identifiers: 51936=EUC-CN; 51950=EUC Traditional Chinese.
  Assert.AreEqual<Integer>(51950, KNOWN_CHARSETS[X_EUC_TW_CHARSET].CodePage);
  Assert.AreEqual('x-euc-tw', string(AnsiString(KNOWN_CHARSETS[X_EUC_TW_CHARSET].Name)));
end;

procedure TChsRegressionTests.Gb18030TailCanRefineACompleteGbkPrefix;
var
  Prefix, Tail: TBytes;
  Detector: IChsEncodingDetector;
  Actual: TChsDetectionResult;
  Split: Integer;
begin
  Prefix := TFile.ReadAllBytes(TPath.Combine(TChsCorpus.DataDir, 'legacy-overlap-gbk.txt'));
  Assert.IsTrue(Length(Prefix) > 1024, 'A full statistical GBK prefix is required');
  Tail := TBytes.Create($81, $30, $81, $30);
  for Split := 0 to Length(Tail) do
  begin
    Detector := TChsEncodingDetector.New;
    Detector.Feed(Prefix);
    Assert.IsFalse(Detector.IsDone, 'A GBK-compatible prefix is not the whole stream');
    Detector.Feed(Tail, 0, Split);
    Detector.Feed(Tail, Split, Length(Tail) - Split);
    Actual := Detector.Finish;
    Assert.AreEqual<Integer>(54936, Actual.CodePage);
    Assert.AreEqual('GB18030', Actual.Name);
  end;
end;

procedure TChsRegressionTests.DisabledGbkKeepsTheCompatibleGb18030Candidate;
var
  Bytes: TBytes;
  Detector: IChsEncodingDetector;
  Actual: TChsDetectionResult;
begin
  Bytes := TFile.ReadAllBytes(TPath.Combine(TChsCorpus.DataDir, 'legacy-overlap-gbk.txt'));
  Assert.IsTrue(Length(Bytes) > 1024);
  Detector := TChsEncodingDetector.New;
  Detector.DisableCodePage(936);
  Detector.Feed(Bytes);
  Actual := Detector.Finish;
  Assert.AreEqual<Integer>(54936, Actual.CodePage);
  Assert.AreEqual('GB18030', Actual.Name);
end;

procedure TChsRegressionTests.FinishIsTerminalAndResetStartsANewDetection;
var
  Detector: IChsEncodingDetector;
  Actual: TChsDetectionResult;
begin
  Detector := TChsEncodingDetector.New;
  Assert.IsFalse(Detector.IsDone);
  Actual := Detector.Finish;
  Assert.IsTrue(Actual.IsUnknown);
  Assert.IsTrue(Detector.IsDone, 'Finish closes even an empty detection');
  Detector.Feed(TBytes.Create($74, $65, $73, $74));
  Actual := Detector.Finish;
  Assert.IsTrue(Actual.IsUnknown, 'More input needs Reset after Finish');
  Detector.Reset;
  Assert.IsFalse(Detector.IsDone);
  Detector.Feed(TBytes.Create($74, $65, $73, $74));
  Actual := Detector.Finish;
  Assert.AreEqual<Integer>(0, Actual.CodePage);
  Assert.AreEqual('ASCII', Actual.Name);
  Assert.IsTrue(Detector.IsDone);
  Actual := Detector.Finish;
  Assert.AreEqual<Integer>(0, Actual.CodePage, 'Repeated Finish is idempotent');
end;

procedure TChsRegressionTests.WholeFeedPreservesTheAsciiPrefixOfAMixedWord;
var
  Bytes: TBytes;
  Actual: TChsDetectionResult;
begin
  // CP1251: ASCII "test" joined directly to Russian "Ostanovka avtobusa".
  // A forced internal split after four bytes incorrectly favors Mac Cyrillic.
  Bytes := TBytes.Create($74, $65, $73, $74, $CE, $F1, $F2, $E0, $ED, $EE,
    $E2, $EA, $E0, $20, $E0, $E2, $F2, $EE, $E1, $F3, $F1, $E0);
  Actual := TChsEncodingDetector.Detect(Bytes);
  Assert.AreEqual<Integer>(1251, Actual.CodePage);
  Assert.AreEqual('windows-1251', Actual.Name);
end;

initialization
  TDUnitX.RegisterTestFixture(TChsRegressionTests);
end.
