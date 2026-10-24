unit ChsDet.ProberTests;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TChsProberTests = class
  public
    [Test] procedure Gb18030FoundCharsetSurvivesConfidenceQueriesAndReset;
    [Test] procedure MultiModelReturnsItsFinalState;
    [Test] procedure UnicodeProberPreservesUtf16AtEverySplit;
    [Test] procedure SingleByteFilterKeepsByte80;
    [Test] procedure Utf16LeModelReportsTwoByteCharacterLengths;
    [Test] procedure SingleByteScoresUseTheCompleteCorpusAtEveryChunkSize;
    [Test] procedure SingleByteConfidenceSaturationIsMonotonic;
    [Test] procedure JapaneseContextConsumesIncompleteTailsExactlyOnce;
    [Test] procedure JapaneseContextDoesNotReadBeyondTheSuppliedBlock;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, nsCore, nsCodingStateMachine, MultiModelProber,
  nsMBCSMultiProber, MBUnicodeMultiProber, nsSBCSGroupProber, ChsDet.Corpus,
  nsSBCharSetProber, LangCyrillicModel, JpCntx, Winapi.Windows;

{$I '../UTF8LangModel.inc'}
{$I '../UCS2LELangModel.inc'}

type
  // A legal protected seam using the production UTF-8 model, not a fake SUT.
  TSingleUtf8ModelProber = class(TMultiModelProber)
  public
    constructor Create; override;
  end;

  TSingleByteConfidenceProbe = class(TnsSingleByteCharSetProber)
  public
    procedure SetSequenceCounts(PositivePairs, TotalPairs: Cardinal);
  end;

function ByteString(const Values: array of Byte): AnsiString;
var
  I: Integer;
begin
  // Write bytes directly: a string literal can pass through Unicode and the
  // active Windows code page before it is assigned to an AnsiString.
  SetLength(Result, Length(Values));
  for I := 0 to High(Values) do
    Result[I + 1] := AnsiChar(Values[I]);
end;

procedure TSingleByteConfidenceProbe.SetSequenceCounts(PositivePairs, TotalPairs: Cardinal);
begin
  // Legal protected seam: attainable counts with all characters in the model.
  // The production GetConfidence method and the real Russian model are intact.
  mTotalSeqs := TotalPairs;
  FillChar(mSeqCounters, SizeOf(mSeqCounters), 0);
  mSeqCounters[0] := TotalPairs - PositivePairs;
  mSeqCounters[3] := PositivePairs;
  mTotalChar := TotalPairs + 1;
  mFreqChar := mTotalChar;
end;

constructor TSingleUtf8ModelProber.Create;
begin
  inherited Create;
  AddCharsetModel(UTF8LangModel);
end;

procedure TChsProberTests.Gb18030FoundCharsetSurvivesConfidenceQueriesAndReset;
var
  Prober: TnsMBCSMultiProber;
  Data: AnsiString;
  Split, Query: Integer;
begin
  // U+0080 in GB18030. Four bytes are a structural GB18030 discriminator;
  // the expected identity does not come from another call to the detector.
  Data := ByteString([$81, $30, $81, $30]);
  Prober := TnsMBCSMultiProber.Create;
  try
    for Split := 0 to Length(Data) do
    begin
      Prober.Reset;
      if Split > 0 then
        Prober.HandleData(PAnsiChar(Data), Split);
      if Split < Length(Data) then
        Prober.HandleData(PAnsiChar(Data) + Split, Length(Data) - Split);
      Assert.AreEqual<Integer>(Ord(psFoundIt), Ord(Prober.GetState));
      Assert.AreEqual<Integer>(Ord(GB18030_CHARSET), Ord(Prober.GetDetectedCharset));
      for Query := 1 to 2 do
      begin
        Assert.IsTrue(Prober.GetConfidence >= SHORTCUT_THRESHOLD,
          'A found structural signature must retain its confidence');
        Assert.AreEqual<Integer>(Ord(GB18030_CHARSET), Ord(Prober.GetDetectedCharset),
          'Reading confidence must not erase the selected charset');
      end;
    end;
    Prober.Reset;
    Assert.AreEqual<Integer>(Ord(UNKNOWN_CHARSET), Ord(Prober.GetDetectedCharset));
    Assert.AreEqual<Double>(SURE_NO, Prober.GetConfidence);
  finally
    Prober.Free;
  end;
end;

procedure TChsProberTests.MultiModelReturnsItsFinalState;
var
  Prober: TSingleUtf8ModelProber;
  Data: AnsiString;
  Returned: eProbingState;
begin
  Data := ByteString([$C3, $A9]); // U+00E9, a complete UTF-8 character.
  Prober := TSingleUtf8ModelProber.Create;
  try
    Returned := Prober.HandleData(PAnsiChar(Data), Length(Data));
    Assert.AreEqual<Integer>(Ord(psFoundIt), Ord(Prober.GetState));
    Assert.AreEqual<Integer>(Ord(Prober.GetState), Ord(Returned),
      'HandleData must return the state it has just selected');
    Assert.AreEqual<Integer>(Ord(UTF8_CHARSET), Ord(Prober.GetDetectedCharset));

    Prober.Reset;
    Returned := Prober.HandleData(nil, 0);
    Assert.AreEqual<Integer>(Ord(psDetecting), Ord(Returned));
    Assert.AreEqual<Integer>(Ord(UNKNOWN_CHARSET), Ord(Prober.GetDetectedCharset),
      'An empty block is not evidence for a charset');
  finally
    Prober.Free;
  end;
end;

procedure TChsProberTests.UnicodeProberPreservesUtf16AtEverySplit;
var
  Prober: TMBUnicodeMultiProber;
  Data: AnsiString;
  Endian, Split: Integer;
  Expected: eInternalCharsetID;
begin
  Prober := TMBUnicodeMultiProber.Create;
  try
    for Endian := 0 to 1 do
    begin
      // Explicit UTF-16 bytes for "AB" + U+00E9 + "-" + CRLF, without a BOM.
      // ASCII-valued bytes, including NULs, must preserve word alignment.
      if Endian = 0 then
      begin
        Data := ByteString([$41, 0, $42, 0, $E9, 0, $2D, 0, $0D, 0, $0A, 0]);
        Expected := UTF16_LE_CHARSET;
      end
      else
      begin
        Data := ByteString([0, $41, 0, $42, 0, $E9, 0, $2D, 0, $0D, 0, $0A]);
        Expected := UTF16_BE_CHARSET;
      end;
      for Split := 0 to Length(Data) do
      begin
        Prober.Reset;
        Prober.HandleData(PAnsiChar(Data), Split);
        Prober.HandleData(PAnsiChar(Data) + Split, Length(Data) - Split);
        Assert.IsTrue(Prober.GetConfidence >= SHORTCUT_THRESHOLD,
          Format('endian=%d split=%d', [Endian, Split]));
        Assert.AreEqual<Integer>(Ord(Expected), Ord(Prober.GetDetectedCharset),
          Format('endian=%d split=%d', [Endian, Split]));
      end;
    end;
  finally
    Prober.Free;
  end;
end;

procedure TChsProberTests.SingleByteFilterKeepsByte80;
var
  Data, Expected: AnsiString;
  Buffer: array [0..31] of AnsiChar;
  Output: PAnsiChar;
  Count, I: Integer;
begin
  // 0x80 is a high byte just like 0x81..0xFF (e.g. Cyrillic A in IBM866).
  // Keep its word, remove ASCII-only words, preserve the word delimiter.
  Data := ByteString([$61, $62, $63, $20, $41, $80, $42, $20, $78, $79, $7A]);
  Expected := ByteString([$41, $80, $42, $20]);
  FillChar(Buffer, SizeOf(Buffer), $CC);
  Output := @Buffer[0];
  Assert.IsTrue(FilterWithoutEnglishLetters(PAnsiChar(Data), Length(Data), Output, Count));
  Assert.AreEqual<Integer>(Length(Expected), Count);
  for I := 0 to Count - 1 do
    Assert.AreEqual<Integer>(Byte(Expected[I + 1]), Byte(Output[I]));
  Assert.AreEqual<Integer>($CC, Byte(Buffer[Count]),
    'The filter must not write beyond its reported payload');
end;

procedure TChsProberTests.Utf16LeModelReportsTwoByteCharacterLengths;
var
  Machine: TnsCodingStateMachine;
  B: Integer;
begin
  Machine := TnsCodingStateMachine.Create(UCS2LELangModel);
  try
    for B := 0 to 255 do
    begin
      Machine.Reset;
      Machine.NextState(AnsiChar(B));
      Assert.AreEqual<Cardinal>(2, Machine.GetCurrentCharLen,
        Format('UTF-16LE first byte %.2x', [B]));
    end;
  finally
    Machine.Free;
  end;
end;

procedure TChsProberTests.SingleByteScoresUseTheCompleteCorpusAtEveryChunkSize;
const
  ChunkSizes: array [0..5] of Integer = (1, 2, 3, 7, 64, 8192);
var
  Prober: TnsSBCSGroupProber;
  Data: TBytes;
  WholeConfidence: Double;
  ChunkSize, Offset, Count: Integer;
begin
  // The corpus manifest independently labels these original bytes as 1251.
  Data := TFile.ReadAllBytes(TPath.Combine(TChsCorpus.DataDir, 'windows-1251.txt'));
  Assert.IsTrue(Length(Data) > 1024, 'The sample must exercise the old shortcut');
  Prober := TnsSBCSGroupProber.Create;
  try
    Prober.HandleData(PAnsiChar(@Data[0]), Length(Data));
    WholeConfidence := Prober.GetConfidence;
    Assert.AreEqual<Integer>(Ord(WINDOWS_1251_CHARSET), Ord(Prober.GetDetectedCharset));

    for ChunkSize in ChunkSizes do
    begin
      Prober.Reset;
      Offset := 0;
      while Offset < Length(Data) do
      begin
        Count := ChunkSize;
        if Count > Length(Data) - Offset then
          Count := Length(Data) - Offset;
        Prober.HandleData(PAnsiChar(@Data[Offset]), Count);
        Inc(Offset, Count);
      end;
      Assert.AreEqual<Double>(WholeConfidence, Prober.GetConfidence,
        Format('The score must include all bytes, chunk=%d', [ChunkSize]));
      Assert.AreEqual<Integer>(Ord(WINDOWS_1251_CHARSET), Ord(Prober.GetDetectedCharset),
        Format('A high-confidence prefix must not freeze another model, chunk=%d', [ChunkSize]));
    end;
  finally
    Prober.Free;
  end;
end;

procedure TChsProberTests.SingleByteConfidenceSaturationIsMonotonic;
var
  Prober: TSingleByteConfidenceProbe;
  Lower, Higher: Double;
begin
  Prober := TSingleByteConfidenceProbe.Create(Win1251Model);
  try
    // 970/1000 and 990/1000 positive pairs bracket the real model's ratio.
    // Increasing positive evidence must not lower the reported confidence.
    Prober.SetSequenceCounts(970, 1000);
    Lower := Prober.GetConfidence;
    Prober.SetSequenceCounts(990, 1000);
    Higher := Prober.GetConfidence;
    Assert.IsTrue(Higher >= Lower, 'More positive evidence must not lower confidence');
    Assert.IsTrue(Lower <= SURE_YES, 'The saturation ceiling applies below raw score 1 too');
    Assert.AreEqual<Double>(SURE_YES, Higher);
  finally
    Prober.Free;
  end;
end;

procedure TChsProberTests.JapaneseContextConsumesIncompleteTailsExactlyOnce;
var
  Analysis: TJapaneseContextAnalysis;
  Lead, Tails, Hiragana: AnsiString;
  Kind, I: Integer;
begin
  for Kind := 0 to 1 do
  begin
    if Kind = 0 then
    begin
      Analysis := TSJISContextAnalysis.Create;
      Lead := ByteString([$82]);
      Tails := ByteString([$A0]);
      Hiragana := ByteString([$82, $A0]); // U+3042 in Shift_JIS.
    end
    else
    begin
      Analysis := TEUCJPContextAnalysis.Create;
      Lead := ByteString([$8F]);
      Tails := ByteString([$A2, $AF]); // JIS X 0212 three-byte character, split twice.
      Hiragana := ByteString([$A4, $A2]); // U+3042 in EUC-JP.
    end;
    try
      Analysis.HandleData(PAnsiChar(Lead), Length(Lead));
      for I := 1 to Length(Tails) do
        Analysis.HandleData(PAnsiChar(Tails) + I - 1, 1);
      for I := 1 to 8 do
        Analysis.HandleData(PAnsiChar(Hiragana), Length(Hiragana));
      Assert.AreEqual<Double>(1.0, Analysis.GetConfidence,
        'A consumed tail must not keep skipping bytes from later characters');

      Analysis.Reset;
      for I := 1 to 8 do
        Analysis.HandleOneChar(PAnsiChar(Hiragana), Length(Hiragana));
      Assert.AreEqual<Double>(1.0, Analysis.GetConfidence,
        'The same complete hiragana pairs have the known positive model category');
    finally
      Analysis.Free;
    end;
  end;
end;

procedure TChsProberTests.JapaneseContextDoesNotReadBeyondTheSuppliedBlock;
var
  Info: TSystemInfo;
  Region: Pointer;
  Lead: PAnsiChar;
  OldProtection: DWORD;
  Analysis: TJapaneseContextAnalysis;
  Hiragana: AnsiString;
  Kind, I: Integer;
begin
  GetSystemInfo(Info);
  Region := VirtualAlloc(nil, NativeUInt(Info.dwPageSize) * 2,
    MEM_RESERVE or MEM_COMMIT, PAGE_READWRITE);
  if Region = nil then
    RaiseLastOSError;
  try
    if not VirtualProtect(PAnsiChar(Region) + Info.dwPageSize,
      Info.dwPageSize, PAGE_NOACCESS, OldProtection) then
      RaiseLastOSError;
    Lead := PAnsiChar(Region) + Info.dwPageSize - 1;
    for Kind := 0 to 1 do
    begin
      if Kind = 0 then
      begin
        Analysis := TSJISContextAnalysis.Create;
        Lead^ := AnsiChar($82);
        Hiragana := ByteString([$82, $A0]);
      end
      else
      begin
        Analysis := TEUCJPContextAnalysis.Create;
        Lead^ := AnsiChar($A4);
        Hiragana := ByteString([$A4, $A2]);
      end;
      try
        // Exactly one readable byte; the next byte is on an inaccessible page.
        // An unexpected access violation must reach the runner unchanged.
        Analysis.HandleData(Lead, 1);
        Assert.AreEqual<Double>(-1.0, Analysis.GetConfidence);
        Analysis.HandleData(PAnsiChar(Hiragana) + 1, 1);
        for I := 1 to 8 do
          Analysis.HandleData(PAnsiChar(Hiragana), 2);
        Assert.AreEqual<Double>(1.0, Analysis.GetConfidence);
      finally
        Analysis.Free;
      end;
    end;
  finally
    VirtualFree(Region, 0, MEM_RELEASE);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TChsProberTests);

end.
