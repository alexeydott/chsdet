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
  public
    [Test] procedure SbcsWordBoundariesSurviveEverySplit;
    [Test] procedure SbcsResetClearsPendingWordState;
    [Test] procedure Latin1SeparatorsSurviveEverySplit;
    [Test] procedure Latin1TagsSurviveEverySplit;
    [Test] procedure Latin1ResetClearsTagStateAndRejectsUndefinedBytes;
    [Test] procedure CorpusSingleByteResultsSurviveSmallChunks;
  end;

implementation

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
