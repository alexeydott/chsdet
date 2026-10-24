unit ChsDet.RegressionTests;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.IOUtils, nsCore,
  ChsDet.Corpus, ChsDet.EncodingDetector, nsUniversalDetector;

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
    [Test] procedure ShortUtf16WithSparseControlsIsStillText;
    [Test] procedure RepeatedOemWordAccentsRemainSupported;
    [Test] procedure SingleSymbolNfoLinesRemainSupported;
    [Test] procedure WesternPunctuationDisambiguatesEmbeddedOemLikeBytes;
    [Test] procedure GraphicRunsMustNotOverrideNonOemContext;
    [Test] procedure SingleByteRunSamplingSurvivesSplitsEofAndReset;
    [Test] procedure AccentedNfoFramesRemainChunkIndependent;
    [Test] procedure ShortSingleByteEmphasisRetainsLiteralEvidence;
    [Test] procedure UnrelatedCornerFragmentsAreNotAnNfoFrame;
    [Test] procedure RepeatedShortEvidenceSurvivesPaddingThreshold;
    [Test] procedure NfoFrameRequiresCompleteAlignedRows;
    [Test] procedure EmptyNormalizedHighByteEvidenceCannotSelectWestern;
    [Test] procedure TabbedFramesRejectCursorControls;
  end;

implementation

procedure TChsRegressionTests.EmptyNormalizedHighByteEvidenceCannotSelectWestern;
const
  Sizes: array [0..3] of Integer = (127, 128, 129, 4096);
  Chunks: array [0..4] of Integer = (1, 3, 7, 128, 8192);
var
  Data: TBytes;
  Size, I, Chunk: Integer;
  Detector: IChsEncodingDetector;
  Expected, Actual: TChsDetectionResult;
begin
  Detector := TChsEncodingDetector.New;
  for Size in Sizes do
  begin
    SetLength(Data, Size);
    FillChar(Data[0], 8, $E0);
    for I := 8 to High(Data) do
      if Odd(I) then Data[I] := Ord('a') else Data[I] := 32;
    Expected := TChsEncodingDetector.Detect(Data);
    if Size > 128 then Assert.AreEqual<Integer>(-1, Expected.CodePage);
    for Chunk in Chunks do
    begin
      Actual := DetectChunks(Data, Chunk);
      Assert.IsTrue(Actual.CodePage <> 1252,
        Format('No Western evidence: size=%d chunk=%d', [Size, Chunk]));
      Assert.AreEqual<Integer>(Expected.CodePage, Actual.CodePage);
      Assert.AreEqual<Double>(Expected.Confidence, Actual.Confidence);
    end;
    Detector.Reset;
    Detector.Feed(TBytes.Create($31, $30, $20, $80));
    Assert.AreEqual<Integer>(1252, Detector.Finish.CodePage);
    Detector.Reset;
    Detector.Feed(Data);
    Assert.AreEqual<Integer>(Expected.CodePage, Detector.Finish.CodePage);
  end;
end;

procedure TChsRegressionTests.TabbedFramesRejectCursorControls;
const
  Chunks: array [0..4] of Integer = (1, 3, 7, 128, 8192);
var
  Prose, Frame, Data: TBytes;
  State: TOemBoxState;
  Kind, Control, I, Offset, Line, Chunk: Integer;
begin
  for Kind := 0 to 1 do
    for Control in [0, 8, 27, 32, 127] do
    begin
      // Aligned byte columns are not a visible frame if cursor controls occur.
      Frame := TBytes.Create(9, $C9, $CD, $CD, $CD, $CD, $CD, $CD, $CD, $CD, $BB, 13, 10,
        9, $BA, 32, 32, 32, Byte(Control), 32, 32, 32, 32, $BA, 13, 10,
        9, $C8, $CD, $CD, $CD, $CD, $CD, $CD, $CD, $CD, $BC);
      FillChar(State, SizeOf(State), 0);
      for I := 0 to High(Frame) do State.Feed(Frame[I]);
      Assert.AreEqual<Boolean>(Control = 32, State.HasFrame,
        'Only the printable variant proves frame geometry');
      Prose := Copy(TFile.ReadAllBytes(TPath.Combine(TChsCorpus.DataDir,
        'windows-1251.txt')), 0, 256);
      if Kind = 1 then
        for I := 0 to High(Prose) do
          case I mod 4 of
            0: Prose[I] := Ord('a');
            1: Prose[I] := $E9;
            2: Prose[I] := $80;
            3: Prose[I] := 32;
          end;
      Data := Append(Append(Prose, TBytes.Create(13, 10)), Frame);
      Data := Append(Data, TBytes.Create(13, 10));
      Offset := Length(Data);
      SetLength(Data, Offset + 4 * 258);
      for Line := 0 to 3 do
      begin
        FillChar(Data[Offset + Line * 258], 256, $DB);
        Data[Offset + Line * 258 + 256] := 13;
        Data[Offset + Line * 258 + 257] := 10;
      end;
      for Chunk in Chunks do
        Assert.AreEqual<Boolean>(Control = 32, DetectChunks(Data, Chunk).CodePage = 437,
          Format('Cursor-controlled pseudo-frame: kind=%d control=%d chunk=%d',
            [Kind, Control, Chunk]));
    end;
end;

procedure TChsRegressionTests.RepeatedShortEvidenceSurvivesPaddingThreshold;
const
  Chunks: array [0..5] of Integer = (1, 2, 3, 7, 128, 8192);
  Sizes: array [0..4] of Integer = (127, 128, 129, 256, 4096);
var
  Data: TBytes;
  Size, I, Chunk, Kind: Integer;
  Expected, Actual: TChsDetectionResult;
begin
  for Kind := 0 to 1 do
    for Size in Sizes do
    begin
      SetLength(Data, Size);
      Data[0] := $C4;
      for I := 1 to 8 do Data[I] := $E0;
      Data[9] := Ord('!');
      if Kind = 0 then FillChar(Data[10], Size - 10, Ord(' '))
      else
      begin
        FillChar(Data[1], Size - 2, $E0);
        Data[Size - 1] := Ord('!');
      end;
      for Chunk in Chunks do
        Assert.AreEqual<Integer>(-1, DetectChunks(Data, Chunk).CodePage,
          Format('Padding must not manufacture a Western label: kind=%d size=%d chunk=%d',
            [Kind, Size, Chunk]));
    end;
  // Exercise the actual evidence-buffer transition as well as raw length.
  for Size := 127 to 129 do
  begin
    SetLength(Data, Size);
    for I := 0 to Size - 1 do
      if Odd(I) then Data[I] := 32 else Data[I] := $80;
    FillChar(Data[8], 8, $E9);
    Expected := TChsEncodingDetector.Detect(Data);
    for Chunk in Chunks do
    begin
      Actual := DetectChunks(Data, Chunk);
      Assert.AreEqual<Integer>(Expected.CodePage, Actual.CodePage);
      Assert.AreEqual<Double>(Expected.Confidence, Actual.Confidence);
    end;
  end;
end;

procedure TChsRegressionTests.NfoFrameRequiresCompleteAlignedRows;
const
  Chunks: array [0..4] of Integer = (1, 3, 7, 128, 8192);
var
  State: TOemBoxState;
  Top, Side, Bottom, Data, Mixed, Prose: TBytes;
  Kind, I, Offset, Line, EncodingKind, Chunk: Integer;
begin
  Top := TBytes.Create($C9, $CD, $CD, $CD, $CD, $CD, $CD, $CD, $CD, $BB, 13, 10);
  Side := TBytes.Create($BA, 32, 32, 32, $82, 32, 32, 32, 32, $BA, 13, 10);
  Bottom := TBytes.Create($C8, $CD, $CD, $CD, $CD, $CD, $CD, $CD, $CD, $BC);
  for Kind := 0 to 6 do
  begin
    Data := Append(Top, Side);
    if Kind <> 1 then Data := Append(Data, Bottom);
    case Kind of
      2: Data := Copy(Data, 0, Length(Data) - 1); // Missing closing corner.
      3: Data[12] := 32; // Missing left side.
      4: Data[21] := 32; // Missing right side.
      5: Data := Append(Append(Top, TBytes.Create(9)), Append(Side, Bottom));
      6: Data := Append(Append(Top, TBytes.Create(32)), Append(Side, Bottom));
    end;
    FillChar(State, SizeOf(State), 0);
    for I := 0 to High(Data) do State.Feed(Data[I]);
    Assert.AreEqual<Boolean>(Kind = 0, State.HasFrame, 'Frame variant=' + IntToStr(Kind));
    for EncodingKind := 0 to 1 do
    begin
      Prose := Copy(TFile.ReadAllBytes(TPath.Combine(TChsCorpus.DataDir,
        'windows-1251.txt')), 0, 256);
      if EncodingKind = 1 then
        for I := 0 to High(Prose) do
          case I mod 4 of
            0: Prose[I] := Ord('a');
            1: Prose[I] := $E9;
            2: Prose[I] := $80;
            3: Prose[I] := 32;
          end;
      Mixed := Append(Append(Prose, TBytes.Create(13, 10)), Data);
      Mixed := Append(Mixed, TBytes.Create(13, 10));
      Offset := Length(Mixed);
      SetLength(Mixed, Offset + 4 * 258);
      for Line := 0 to 3 do
      begin
        FillChar(Mixed[Offset + Line * 258], 256, $DB);
        Mixed[Offset + Line * 258 + 256] := 13;
        Mixed[Offset + Line * 258 + 257] := 10;
      end;
      for Chunk in Chunks do
        Assert.AreEqual<Boolean>(Kind = 0, DetectChunks(Mixed, Chunk).CodePage = 437,
          Format('Frame exception: kind=%d encoding=%d chunk=%d',
            [Kind, EncodingKind, Chunk]));
    end;
  end;
  // A tab and eight spaces represent the same visual indentation.
  Data := Append(Append(TBytes.Create(9), Top),
    Append(Append(TBytes.Create(32,32,32,32,32,32,32,32), Side),
      Append(TBytes.Create(9), Bottom)));
  FillChar(State, SizeOf(State), 0);
  for I := 0 to High(Data) do State.Feed(Data[I]);
  Assert.IsTrue(State.HasFrame, 'Aligned tab/space indentation');
  Data := Append(Append(TBytes.Create(9), Top),
    Append(Append(TBytes.Create(32), Side), Append(TBytes.Create(9), Bottom)));
  FillChar(State, SizeOf(State), 0);
  for I := 0 to High(Data) do State.Feed(Data[I]);
  Assert.IsFalse(State.HasFrame, 'One space must not align with a tab');
end;

procedure TChsRegressionTests.ShortSingleByteEmphasisRetainsLiteralEvidence;
const
  Chunks: array [0..5] of Integer = (1, 2, 3, 7, 64, 8192);
var
  Data: TBytes;
  Kind, I, Chunk: Integer;
  Expected, Actual: TChsDetectionResult;
begin
  for Kind := 0 to 1 do
  begin
    if Kind = 0 then
    begin
      // CP1251 "Daaaaaaa!", an expressive short word rather than padding.
      SetLength(Data, 10);
      Data[0] := $C4;
      for I := 1 to 8 do Data[I] := $E0;
      Data[9] := Ord('!');
    end
    else
    begin
      Data := TBytes.Create($31, $30, $20, $80, $80, $80, $80, $80, $80, $80, $80);
    end;
    for Chunk in Chunks do
      if Kind = 0 then
        // Too little evidence for an exact label, but not Western prose.
        Assert.AreEqual<Integer>(-1, DetectChunks(Data, Chunk).CodePage,
          'Ambiguous emphatic word must remain unknown')
      else
        Assert.AreEqual<Integer>(1252, DetectChunks(Data, Chunk).CodePage,
          Format('Short literal evidence: kind=%d chunk=%d', [Kind, Chunk]));
  end;
  // Crossing the bounded literal-prefix threshold must not depend on chunks.
  for I := 127 to 129 do
  begin
    Data := TBytes.Create($31, $30, $20, $80, $80, $80, $80, $80, $80, $80, $80);
    SetLength(Data, I);
    FillChar(Data[11], I - 11, Ord(' '));
    Expected := TChsEncodingDetector.Detect(Data);
    for Chunk in Chunks do
    begin
      Actual := DetectChunks(Data, Chunk);
      Assert.AreEqual<Integer>(Expected.CodePage, Actual.CodePage);
      Assert.AreEqual<Double>(Expected.Confidence, Actual.Confidence);
    end;
  end;
end;

procedure TChsRegressionTests.UnrelatedCornerFragmentsAreNotAnNfoFrame;
const
  Chunks: array [0..5] of Integer = (1, 2, 3, 7, 64, 8192);
var
  Data, Prose: TBytes;
  I, Line, Chunk, Kind: Integer;
begin
  for Kind := 0 to 1 do
  begin
    Prose := TFile.ReadAllBytes(TPath.Combine(TChsCorpus.DataDir, 'windows-1251.txt'));
    Data := Copy(Prose, 0, 256);
    if Kind = 1 then
      for I := 0 to High(Data) do
        case I mod 4 of
          0: Data[I] := Ord('a');
          1: Data[I] := $E9;
          2: Data[I] := $80;
          3: Data[I] := 32;
        end;
    // Corner-like letter triples scattered in prose, not a rectangular frame.
    Data := Append(Data, [13, 10, $C9, $CD, $CD, $20, $61, 13, 10,
      $62, $20, $CD, $CD, $BB, 13, 10, $BA, $20, $63, 13, 10]);
    I := Length(Data);
    SetLength(Data, I + 4 * 514);
    for Line := 0 to 3 do
    begin
      FillChar(Data[I + Line * 514], 512, $DB);
      Data[I + Line * 514 + 512] := 13;
      Data[I + Line * 514 + 513] := 10;
    end;
    for Chunk in Chunks do
      Assert.IsTrue(DetectChunks(Data, Chunk).CodePage <> 437,
        'Scattered letter triples must not bypass prose protection, chunk=' + IntToStr(Chunk));
  end;
end;

procedure TChsRegressionTests.SingleByteRunSamplingSurvivesSplitsEofAndReset;
const
  Chunks: array [0..6] of Integer = (1, 2, 3, 7, 64, 257, 8192);
var
  Prose, Data: TBytes;
  Detector: IChsEncodingDetector;
  Expected, Actual: TChsDetectionResult;
  RunLength, Split, Chunk: Integer;
begin
  Prose := TFile.ReadAllBytes(TPath.Combine(TChsCorpus.DataDir, 'windows-1251.txt'));
  Detector := TChsEncodingDetector.New;
  RunLength := 8;
  while RunLength <= 4096 do
  begin
    Data := Copy(Prose, 0, 256);
    SetLength(Data, 256 + RunLength);
    FillChar(Data[256], RunLength, $DB);
    Expected := TChsEncodingDetector.Detect(Data);
    Assert.AreEqual<Integer>(1251, Expected.CodePage);
    for Chunk in Chunks do
    begin
      Actual := DetectChunks(Data, Chunk);
      Assert.AreEqual<Integer>(1251, Actual.CodePage);
      Assert.AreEqual<Double>(Expected.Confidence, Actual.Confidence);
    end;
    if RunLength = 8 then
      for Split := 0 to Length(Data) do
      begin
        Detector.Reset;
        Detector.Feed(Data, 0, Split);
        Detector.Feed(Data, Split, Length(Data) - Split);
        Actual := Detector.Finish;
        Assert.AreEqual<Integer>(1251, Actual.CodePage, 'split=' + IntToStr(Split));
        Assert.AreEqual<Double>(Expected.Confidence, Actual.Confidence);
      end;
    Detector.Reset;
    Detector.Feed(TBytes.Create($DB, $DB, $DB, $DB, $DB, $DB, $DB, $DB));
    Detector.Reset;
    Detector.Feed(Data);
    Actual := Detector.Finish;
    Assert.AreEqual<Integer>(1251, Actual.CodePage);
    Assert.AreEqual<Double>(Expected.Confidence, Actual.Confidence);
    Assert.AreEqual<Double>(Actual.Confidence, Detector.Finish.Confidence);
    RunLength := RunLength * 512;
  end;
end;

procedure TChsRegressionTests.AccentedNfoFramesRemainChunkIndependent;
const
  Chunks: array [0..6] of Integer = (1, 2, 3, 7, 64, 257, 8192);
var
  Data: TBytes;
  Chunk: Integer;
begin
  Data := TFile.ReadAllBytes(TPath.Combine(TChsCorpus.DataDir, 'cp437-small-nfo-art.txt'));
  for Chunk in Chunks do
    Assert.AreEqual<Integer>(437, DetectChunks(Data, Chunk).CodePage,
      'Accented framed NFO, chunk=' + IntToStr(Chunk));
end;

procedure TChsRegressionTests.WesternPunctuationDisambiguatesEmbeddedOemLikeBytes;
const
  Chunks: array [0..3] of Integer = (1, 3, 64, 8192);
var
  Data, WordBytes: TBytes;
  Kind, I, Chunk: Integer;
begin
  for Kind := 0 to 1 do
  begin
    // Independent Western evidence: a standalone CP1252 euro and em dash.
    WordBytes := TBytes.Create($66, $61, $87, $61, $64, $65, $20, $31, $30, $20,
      $80, $20, $97, $20);
    if Kind = 1 then WordBytes[2] := $A0;
    SetLength(Data, Length(WordBytes) * 100);
    for I := 0 to 99 do
      Move(WordBytes[0], Data[I * Length(WordBytes)], Length(WordBytes));
    for Chunk in Chunks do
      Assert.AreEqual<Integer>(1252, DetectChunks(Data, Chunk).CodePage,
        Format('Western punctuation: kind=%d chunk=%d', [Kind, Chunk]));
    // The sole disambiguating punctuation may arrive as the final byte.
    WordBytes := TBytes.Create($66, $61, $87, $61, $64, $65, $20);
    if Kind = 1 then WordBytes[2] := $A0;
    SetLength(Data, Length(WordBytes) * 100);
    for I := 0 to 99 do
      Move(WordBytes[0], Data[I * Length(WordBytes)], Length(WordBytes));
    Data := Append(Data, [$31, $30, $20, $80]);
    for Chunk in Chunks do
      Assert.AreEqual<Integer>(1252, DetectChunks(Data, Chunk).CodePage,
        Format('Trailing Western punctuation: kind=%d chunk=%d', [Kind, Chunk]));
  end;
end;

procedure TChsRegressionTests.GraphicRunsMustNotOverrideNonOemContext;
const
  Chunks: array [0..3] of Integer = (1, 3, 64, 8192);
  RunLengths: array [0..3] of Integer = (8, 31, 512, 4096);
  WesternText: array [0..17] of Byte =
    ($52, $E9, $73, $75, $6D, $E9, $20, $63, $61, $66, $E9, $20, $31, $30, $20, $80, $2E, $20);
var
  Data, Prose: TBytes;
  Line, I, Chunk, Kind, RunLength: Integer;
  Actual: TChsDetectionResult;
begin
  // CP1251 prose is independent of the ambiguous repeated high-byte rows.
  for Kind := 0 to 1 do
  begin
    if Kind = 0 then
      Prose := TFile.ReadAllBytes(TPath.Combine(TChsCorpus.DataDir, 'windows-1251.txt'))
    else
    begin
      SetLength(Prose, 288);
      for I := 0 to High(Prose) do Prose[I] := WesternText[I mod Length(WesternText)];
    end;
    for RunLength in RunLengths do
    begin
      Data := Copy(Prose, 0, 256);
      SetLength(Data, 256 + 4 * (RunLength + 2));
      for Line := 0 to 3 do
      begin
        for I := 0 to RunLength - 1 do Data[256 + Line * (RunLength + 2) + I] := $DB;
        Data[256 + Line * (RunLength + 2) + RunLength] := 13;
        Data[256 + Line * (RunLength + 2) + RunLength + 1] := 10;
      end;
      for Chunk in Chunks do
      begin
        Actual := DetectChunks(Data, Chunk);
        Assert.IsTrue((Actual.CodePage <> 437) and (Actual.CodePage <> 850) and
          (Actual.CodePage <> 852) and (Actual.CodePage <> 858),
          Format('Graphic-like repetitions must not erase prose: kind=%d chunk=%d', [Kind, Chunk]));
        if Kind = 0 then Assert.AreEqual<Integer>(1251, Actual.CodePage,
          'Cyrillic prose must retain its exact label despite repeated rows')
        else Assert.AreEqual<Integer>(1252, Actual.CodePage,
          'Western prose must retain its exact label despite repeated rows');
      end;
    end;
  end;
end;

procedure TChsRegressionTests.ShortUtf16WithSparseControlsIsStillText;
const
  Chunks: array [0..3] of Integer = (1, 3, 64, 8192);
var
  Data: TBytes;
  Text: string;
  Endian, Kind, Chunk: Integer;
  Encoding: TEncoding;
begin
  for Endian := 0 to 1 do
  begin
    if Endian = 0 then Encoding := TEncoding.Unicode
    else Encoding := TEncoding.BigEndianUnicode;
    for Kind := 0 to 1 do
    begin
      if Kind = 0 then Text := Char($E9) + 'ABC' + #0 + 'DEF'
      else Text := Char($E9) + #27 + '[31mOK' + #27 + '[0m';
      Data := Encoding.GetBytes(Text);
      for Chunk in Chunks do
        Assert.AreEqual<Integer>(1200 + Endian, DetectChunks(Data, Chunk).CodePage,
          Format('Short text: endian=%d kind=%d chunk=%d', [Endian, Kind, Chunk]));
    end;
  end;
end;

procedure TChsRegressionTests.RepeatedOemWordAccentsRemainSupported;
const
  Chunks: array [0..3] of Integer = (1, 3, 64, 8192);
var
  Data, WordBytes: TBytes;
  I, Kind, Chunk: Integer;
begin
  // Literal bytes for "facade" with c-cedilla, "zaklad" with a-acute,
  // and the same French word followed by a euro price in CP858.
  for Kind := 0 to 2 do
  begin
    if Kind = 0 then WordBytes := TBytes.Create($66, $61, $87, $61, $64, $65, $20)
    else if Kind = 1 then WordBytes := TBytes.Create($7A, $A0, $6B, $6C, $61, $64, $20)
    else WordBytes := TBytes.Create($66, $61, $87, $61, $64, $65, $20, $31, $30, $20, $D5, $20);
    SetLength(Data, Length(WordBytes) * 100);
    for I := 0 to 99 do
      Move(WordBytes[0], Data[I * Length(WordBytes)], Length(WordBytes));
    for Chunk in Chunks do
      if Kind = 0 then Assert.AreEqual<Integer>(850, DetectChunks(Data, Chunk).CodePage)
      else if Kind = 1 then Assert.AreEqual<Integer>(852, DetectChunks(Data, Chunk).CodePage)
      else Assert.AreEqual<Integer>(858, DetectChunks(Data, Chunk).CodePage);
  end;
end;

procedure TChsRegressionTests.SingleSymbolNfoLinesRemainSupported;
const
  Chunks: array [0..3] of Integer = (1, 3, 64, 8192);
var
  Data: TBytes;
  I, Line, Chunk, Terminated: Integer;
begin
  SetLength(Data, 68);
  for Line := 0 to 1 do
  begin
    for I := 0 to 31 do Data[Line * 34 + I] := $DB;
    Data[Line * 34 + 32] := 13;
    Data[Line * 34 + 33] := 10;
  end;
  for Terminated := 1 downto 0 do
  begin
    if Terminated = 0 then SetLength(Data, Length(Data) - 2);
    for Chunk in Chunks do
      Assert.AreEqual<Integer>(437, DetectChunks(Data, Chunk).CodePage,
        Format('Repeated NFO lines: terminated=%d chunk=%d', [Terminated, Chunk]));
  end;
end;

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
