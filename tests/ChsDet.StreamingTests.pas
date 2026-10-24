unit ChsDet.StreamingTests;

interface

uses
  DUnitX.TestFramework,
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  ChsDet.Corpus,
  ChsDet.EncodingDetector,
  nsCore,
  CustomDetector,
  nsSBCSGroupProber,
  nsLatin1Prober;

type
  [TestFixture]
  TChsStreamingTests = class
  private
    class function LoadFixture(const Name: string): TBytes; static;
    class function ByteString(const Values: array of Byte): RawByteString; static;
    class procedure FeedSplit(Probe: TCustomDetector; const Data: RawByteString;
      Split: Integer); static;
    class procedure CheckLatin1Splits(const Data: RawByteString); static;
    class procedure CheckMixedWordSplits(const Data: RawByteString;
      AllSplits: Boolean = True); static;
  public
    [Test] procedure SbcsWordBoundariesSurviveEverySplit;
    [Test] procedure SbcsResetClearsPendingWordState;
    [Test] procedure Latin1SeparatorsSurviveEverySplit;
    [Test] procedure Latin1TagsSurviveEverySplit;
    [Test] procedure Latin1ResetClearsTagStateAndRejectsUndefinedBytes;
    [Test] procedure CorpusSingleByteResultsSurviveSmallChunks;
    [Test] procedure SbcsMixedWordsPreserveEveryModelAtEverySplit;
    [Test] procedure SbcsPendingAsciiIsDiscardedAtDelimiterAndReset;
    [Test] procedure SbcsLongAsciiPrefixSurvivesSmallChunks;
    [Test] procedure PublicMixedWordResultsSurviveEverySplit;
  end;

implementation

type
  TInspectableSbcsProber = class(TnsSBCSGroupProber)
  public
    procedure CheckModelsAgainst(Expected: TInspectableSbcsProber; const Context: string);
  end;

procedure TInspectableSbcsProber.CheckModelsAgainst(Expected: TInspectableSbcsProber;
  const Context: string);
var
  I: Integer;
begin
  for I := 0 to mNumOfProbers - 1 do
  begin
    Assert.IsTrue(Abs(mProbers[I].GetConfidence - Expected.mProbers[I].GetConfidence) < 1E-12,
      Format('%s model=%d: confidence differs', [Context, I]));
    Assert.AreEqual<Integer>(Ord(Expected.mProbers[I].GetDetectedCharset),
      Ord(mProbers[I].GetDetectedCharset), Format('%s model=%d: charset differs', [Context, I]));
  end;
end;

class procedure TChsStreamingTests.CheckMixedWordSplits(const Data: RawByteString;
  AllSplits: Boolean);
const
  Chunks: array [0..4] of Integer = (1, 2, 3, 7, 64);
var
  Expected, Actual: TInspectableSbcsProber;
  Split, SplitLimit, Chunk, Offset, Count: Integer;
begin
  Expected := TInspectableSbcsProber.Create;
  Actual := TInspectableSbcsProber.Create;
  try
    Expected.HandleData(PAnsiChar(Data), Length(Data));
    SplitLimit := Length(Data);
    if not AllSplits then
      SplitLimit := 0;
    for Split := 0 to SplitLimit do
    begin
      Actual.Reset;
      FeedSplit(Actual, Data, Split);
      Actual.CheckModelsAgainst(Expected, 'split=' + IntToStr(Split));
    end;
    for Chunk in Chunks do
    begin
      Actual.Reset;
      Offset := 0;
      while Offset < Length(Data) do
      begin
        Count := Chunk;
        if Count > Length(Data) - Offset then
          Count := Length(Data) - Offset;
        Actual.HandleData(PAnsiChar(Data) + Offset, Count);
        // Querying confidence must not flush an unfinished ASCII-only word.
        Actual.GetConfidence;
        Inc(Offset, Count);
      end;
      Actual.CheckModelsAgainst(Expected, 'chunk=' + IntToStr(Chunk));
    end;
  finally
    Actual.Free;
    Expected.Free;
  end;
end;

procedure TChsStreamingTests.SbcsMixedWordsPreserveEveryModelAtEverySplit;
var
  Mixed: RawByteString;
begin
  Mixed := 'test' + ByteString([$CE, $F1, $F2, $E0, $ED, $EE, $E2, $EA, $E0]) + 'tail';
  CheckMixedWordSplits(Mixed);
  CheckMixedWordSplits(Mixed + ' trailingAsciiOnlyWord');
  CheckMixedWordSplits('ASCII only ' + Mixed + #0 + 'end' + ByteString([$E0, $E2, $F2, $EE]));
  CheckMixedWordSplits('prefix' + ByteString([$E1, $EB, $EE, $ED]) + 'suffix ' +
    'english!prefix' + ByteString([$E0, $E1, $E2, $E3]) + #13#10);
  CheckMixedWordSplits('ascii only trailing word');
end;

procedure TChsStreamingTests.SbcsPendingAsciiIsDiscardedAtDelimiterAndReset;
var
  Expected, Actual: TInspectableSbcsProber;
  Data, Prefix: RawByteString;
begin
  Expected := TInspectableSbcsProber.Create;
  Actual := TInspectableSbcsProber.Create;
  try
    Data := ByteString([$CE, $F1, $F2, $E0, $ED, $EE, $E2, $EA, $E0]);
    Expected.HandleData(PAnsiChar(Data), Length(Data));
    Prefix := 'discard';
    Actual.HandleData(PAnsiChar(Prefix), Length(Prefix));
    Actual.HandleData(' ', 1);
    Actual.HandleData(PAnsiChar(Data), Length(Data));
    Actual.CheckModelsAgainst(Expected, 'delimiter discards ASCII-only prefix');
    Actual.Reset;
    Actual.HandleData(PAnsiChar(Prefix), Length(Prefix));
    Actual.Reset;
    Actual.HandleData(PAnsiChar(Data), Length(Data));
    Actual.CheckModelsAgainst(Expected, 'reset discards pending prefix');
  finally
    Actual.Free;
    Expected.Free;
  end;
end;

procedure TChsStreamingTests.SbcsLongAsciiPrefixSurvivesSmallChunks;
var
  Data: RawByteString;
begin
  // Exercise buffer growth across many blocks, including a word at EOF.
  Data := RawByteString(StringOfChar('a', 8193)) + ByteString([$E0, $E1, $E2, $E3]);
  CheckMixedWordSplits(Data, False);
end;

procedure TChsStreamingTests.PublicMixedWordResultsSurviveEverySplit;
const
  Chunks: array [0..4] of Integer = (1, 2, 3, 7, 64);
var
  Data: RawByteString;
  Detector: IChsEncodingDetector;
  Expected, Actual: TChsDetectionResult;
  Split, Chunk, Offset, Count: Integer;
begin
  // Independently labelled CP1251 regression: "test" joined to Russian text.
  Data := 'test' + ByteString([$CE, $F1, $F2, $E0, $ED, $EE, $E2, $EA, $E0,
    $20, $E0, $E2, $F2, $EE, $E1, $F3, $F1, $E0]);
  Detector := TChsEncodingDetector.New;
  Detector.Feed(Data[1], Length(Data));
  Expected := Detector.Finish;
  Assert.AreEqual<Integer>(1251, Expected.CodePage);
  for Split := 0 to Length(Data) do
  begin
    Detector.Reset;
    if Split > 0 then
      Detector.Feed(Data[1], Split);
    if Split < Length(Data) then
      Detector.Feed(Data[Split + 1], Length(Data) - Split);
    Actual := Detector.Finish;
    Assert.AreEqual<Integer>(1251, Actual.CodePage, 'split=' + IntToStr(Split));
    Assert.IsTrue(Abs(Expected.Confidence - Actual.Confidence) < 1E-12);
  end;
  for Chunk in Chunks do
  begin
    Detector.Reset;
    Offset := 0;
    while Offset < Length(Data) do
    begin
      Count := Chunk;
      if Count > Length(Data) - Offset then
        Count := Length(Data) - Offset;
      Detector.Feed(Data[Offset + 1], Count);
      Inc(Offset, Count);
    end;
    Actual := Detector.Finish;
    Assert.AreEqual<Integer>(1251, Actual.CodePage, 'chunk=' + IntToStr(Chunk));
    Assert.IsTrue(Abs(Expected.Confidence - Actual.Confidence) < 1E-12);
  end;
end;

class function TChsStreamingTests.LoadFixture(const Name: string): TBytes;
begin
  Result := TFile.ReadAllBytes(TPath.Combine(TChsCorpus.DataDir, Name));
  Assert.IsTrue(Length(Result) > 512, Name + ': a nonempty corpus sample is required');
end;

class function TChsStreamingTests.ByteString(const Values: array of Byte): RawByteString;
begin
  SetLength(Result, Length(Values));
  if Length(Values) > 0 then
    Move(Values[0], Result[1], Length(Values));
end;

class procedure TChsStreamingTests.FeedSplit(Probe: TCustomDetector;
  const Data: RawByteString; Split: Integer);
begin
  if Split > 0 then
    Probe.HandleData(PAnsiChar(Data), Split);
  if Split < Length(Data) then
    Probe.HandleData(PAnsiChar(Data) + Split, Length(Data) - Split);
end;

procedure TChsStreamingTests.SbcsWordBoundariesSurviveEverySplit;
const
  Names: array[0..1] of string = ('windows-1253-no-c1.txt', 'iso-8859-8.txt');
  CodePages: array[0..1] of Integer = (1253, 28598);
var
  Probe: TnsSBCSGroupProber;
  Bytes: TBytes;
  Data: RawByteString;
  ExpectedConfidence, ActualConfidence: Double;
  I, Split, J: Integer;
begin
  // 512 bytes stay below the statistical shortcut's 1024-pair threshold.
  // The independent charset oracle is the corpus manifest; confidence equality
  // checks that physical chunk boundaries do not invent cross-word bigrams.
  Probe := TnsSBCSGroupProber.Create;
  try
    for I := Low(Names) to High(Names) do
    begin
      Bytes := LoadFixture(Names[I]);
      SetString(Data, PAnsiChar(@Bytes[0]), 512);
      Probe.Reset;
      Probe.HandleData(PAnsiChar(Data), Length(Data));
      ExpectedConfidence := Probe.GetConfidence;
      Assert.AreEqual<Integer>(CodePages[I], KNOWN_CHARSETS[Probe.GetDetectedCharset].CodePage);
      Assert.IsTrue(ExpectedConfidence > 0.9);
      for Split := 0 to Length(Data) do
      begin
        Probe.Reset;
        FeedSplit(Probe, Data, Split);
        ActualConfidence := Probe.GetConfidence;
        Assert.AreEqual<Integer>(CodePages[I], KNOWN_CHARSETS[Probe.GetDetectedCharset].CodePage,
          Names[I] + ' split ' + IntToStr(Split));
        Assert.IsTrue(Abs(ExpectedConfidence - ActualConfidence) < 1E-12,
          Names[I] + ': word-boundary statistics changed at split ' + IntToStr(Split));
      end;
      Probe.Reset;
      for J := 1 to Length(Data) do
        Probe.HandleData(@Data[J], 1);
      ActualConfidence := Probe.GetConfidence;
      Assert.AreEqual<Integer>(CodePages[I], KNOWN_CHARSETS[Probe.GetDetectedCharset].CodePage);
      Assert.IsTrue(Abs(ExpectedConfidence - ActualConfidence) < 1E-12);
    end;
  finally
    Probe.Free;
  end;
end;

procedure TChsStreamingTests.SbcsResetClearsPendingWordState;
var
  Probe: TnsSBCSGroupProber;
  Bytes: TBytes;
  Data, Prefix: RawByteString;
  ExpectedConfidence: Double;
begin
  Bytes := LoadFixture('windows-1253-no-c1.txt');
  SetString(Data, PAnsiChar(@Bytes[0]), 512);
  Prefix := 'ASCII ';
  Data := Prefix + Data;
  Prefix := ByteString([$E0]);
  Probe := TnsSBCSGroupProber.Create;
  try
    Probe.HandleData(PAnsiChar(Data), Length(Data));
    ExpectedConfidence := Probe.GetConfidence;
    Assert.AreEqual<Integer>(1253, KNOWN_CHARSETS[Probe.GetDetectedCharset].CodePage);
    Probe.Reset;
    Probe.HandleData(PAnsiChar(Prefix), Length(Prefix));
    Probe.Reset;
    Probe.HandleData(PAnsiChar(Data), Length(Data));
    Assert.IsTrue(Abs(ExpectedConfidence - Probe.GetConfidence) < 1E-12);
    Assert.AreEqual<Integer>(1253, KNOWN_CHARSETS[Probe.GetDetectedCharset].CodePage);
  finally
    Probe.Free;
  end;
end;

class procedure TChsStreamingTests.CheckLatin1Splits(const Data: RawByteString);
var
  Probe: TnsLatin1Prober;
  Split, I: Integer;
begin
  Assert.IsTrue(Length(Data) > 0);
  Probe := TnsLatin1Prober.Create;
  try
    for Split := 0 to Length(Data) do
    begin
      Probe.Reset;
      FeedSplit(Probe, Data, Split);
      Assert.AreEqual<Integer>(Ord(psDetecting), Ord(Probe.GetState), 'Split ' + IntToStr(Split));
      // These literals contain only category-3 transitions outside tags.
      // Their model confidence is exactly 1 * the Latin1 weighting (0.5).
      Assert.IsTrue(Abs(0.5 - Probe.GetConfidence) < 1E-12, 'Split ' + IntToStr(Split));
      Assert.AreEqual<Integer>(1252, KNOWN_CHARSETS[Probe.GetDetectedCharset].CodePage);
    end;
    Probe.Reset;
    for I := 1 to Length(Data) do
      Probe.HandleData(@Data[I], 1);
    Assert.AreEqual<Integer>(Ord(psDetecting), Ord(Probe.GetState));
    Assert.IsTrue(Abs(0.5 - Probe.GetConfidence) < 1E-12);
  finally
    Probe.Free;
  end;
end;

procedure TChsStreamingTests.Latin1SeparatorsSurviveEverySplit;
begin
  CheckLatin1Splits(ByteString([$E9, $20, $41, $20, $E9, $20, $42, $20,
    $E9, $20, $43, $20]));
end;

procedure TChsStreamingTests.Latin1TagsSurviveEverySplit;
begin
  CheckLatin1Splits(ByteString([$6E, $6F, $72, $6D, $61, $6C, $20, $3C,
    $71, $20, $74, $69, $74, $6C, $65, $3D, $22, $81, $22, $3E, $74, $65,
    $78, $74, $3C, $2F, $71, $3E, $20, $63, $61, $66, $65, $E9, $2E]));
end;

procedure TChsStreamingTests.Latin1ResetClearsTagStateAndRejectsUndefinedBytes;
var
  Probe: TnsLatin1Prober;
  Data: RawByteString;
begin
  Probe := TnsLatin1Prober.Create;
  try
    Data := '<q title="';
    Probe.HandleData(PAnsiChar(Data), Length(Data));
    Probe.Reset;
    Data := ByteString([$81]); // Undefined in windows-1252, now outside any tag.
    Assert.AreEqual<Integer>(Ord(psNotMe), Ord(Probe.HandleData(PAnsiChar(Data), Length(Data))));
    Assert.IsTrue(Abs(SURE_NO - Probe.GetConfidence) < 1E-12);
    Probe.Reset;
    Data := ByteString([$E9, $20, $41, $20]);
    Probe.HandleData(PAnsiChar(Data), Length(Data));
    Assert.AreEqual<Integer>(Ord(psDetecting), Ord(Probe.GetState));
    Assert.IsTrue(Abs(0.5 - Probe.GetConfidence) < 1E-12);
  finally
    Probe.Free;
  end;
end;

procedure TChsStreamingTests.CorpusSingleByteResultsSurviveSmallChunks;
const
  Names: array[0..2] of string = ('windows-1251.txt', 'windows-1253-no-c1.txt', 'iso-8859-8.txt');
  ExpectedNames: array[0..2] of string = ('windows-1251', 'windows-1253', 'ISO-8859-8');
  CodePages: array[0..2] of Integer = (1251, 1253, 28598);
  Chunks: array[0..4] of Integer = (1, 2, 3, 7, 64);
var
  Detector: IChsEncodingDetector;
  Bytes: TBytes;
  Actual: TChsDetectionResult;
  I, Chunk, Offset, Count: Integer;
begin
  Detector := TChsEncodingDetector.New;
  for I := Low(Names) to High(Names) do
  begin
    Bytes := LoadFixture(Names[I]);
    for Chunk in Chunks do
    begin
      Detector.Reset;
      Offset := 0;
      while Offset < Length(Bytes) do
      begin
        Count := Chunk;
        if Count > Length(Bytes) - Offset then
          Count := Length(Bytes) - Offset;
        Detector.Feed(Bytes, Offset, Count);
        Inc(Offset, Count);
      end;
      Actual := Detector.Finish;
      Assert.AreEqual<Integer>(CodePages[I], Actual.CodePage, Names[I] + ' chunk ' + IntToStr(Chunk));
      Assert.AreEqual(ExpectedNames[I], Actual.Name, False, Names[I]);
      Assert.IsFalse(Actual.HasBom);
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TChsStreamingTests);
end.
