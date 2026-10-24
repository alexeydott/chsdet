program ProberProbe;

uses
  SysUtils, Classes, nsCore, nsCodingStateMachine, MultiModelProber,
  nsMBCSMultiProber, MBUnicodeMultiProber, nsSBCSGroupProber,
  nsSBCharSetProber, LangCyrillicModel, JpCntx;

function mmap(Addr: Pointer; Len: NativeUInt; Prot, Flags, Fd: Integer;
  Offset: Int64): Pointer; cdecl; external 'c';
function mprotect(Addr: Pointer; Len: NativeUInt; Prot: Integer): Integer; cdecl; external 'c';
function munmap(Addr: Pointer; Len: NativeUInt): Integer; cdecl; external 'c';
function getpagesize: Integer; cdecl; external 'c';

{$I 'UTF8LangModel.inc'}
{$I 'UCS2LELangModel.inc'}

type
  TTestProc = procedure;
  TSingleUtf8ModelProber = class(TMultiModelProber)
  public
    constructor Create; override;
  end;
  TSingleByteConfidenceProbe = class(TnsSingleByteCharSetProber)
  public
    procedure SetSequenceCounts(PositivePairs, TotalPairs: Cardinal);
  end;

var
  TestsRun, Failures: Integer;

constructor TSingleUtf8ModelProber.Create;
begin
  inherited Create;
  AddCharsetModel(UTF8LangModel);
end;

procedure TSingleByteConfidenceProbe.SetSequenceCounts(PositivePairs, TotalPairs: Cardinal);
begin
  mTotalSeqs := TotalPairs;
  FillChar(mSeqCounters, SizeOf(mSeqCounters), 0);
  mSeqCounters[0] := TotalPairs - PositivePairs;
  mSeqCounters[3] := PositivePairs;
  mTotalChar := TotalPairs + 1;
  mFreqChar := mTotalChar;
end;

procedure Check(Condition: Boolean; const Message: string);
begin
  if not Condition then
    raise Exception.Create(Message);
end;

procedure Run(const Name: string; TestProc: TTestProc);
begin
  Inc(TestsRun);
  try
    TestProc;
    Writeln('PASS ', Name);
  except
    on E: Exception do
    begin
      Inc(Failures);
      Writeln('FAIL ', Name, ': ', E.ClassName, ': ', E.Message);
    end;
  end;
end;

procedure Gb18030Confidence;
var
  Prober: TnsMBCSMultiProber;
  Data: AnsiString;
  Split, Query: Integer;
begin
  Data := #$81#$30#$81#$30; // GB18030 U+0080.
  Prober := TnsMBCSMultiProber.Create;
  try
    for Split := 0 to Length(Data) do
    begin
      Prober.Reset;
      if Split > 0 then
        Prober.HandleData(PAnsiChar(Data), Split);
      if Split < Length(Data) then
        Prober.HandleData(PAnsiChar(Data) + Split, Length(Data) - Split);
      Check(Prober.GetState = psFoundIt, 'Structural GB18030 was not found');
      Check(Prober.GetDetectedCharset = GB18030_CHARSET, 'Wrong GB18030 identity');
      for Query := 1 to 2 do
      begin
        Check(Prober.GetConfidence >= SHORTCUT_THRESHOLD,
          'Reading confidence lost the structural GB18030 evidence');
        Check(Prober.GetDetectedCharset = GB18030_CHARSET,
          'Reading confidence changed the GB18030 identity');
      end;
    end;
    Prober.Reset;
    Check(Prober.GetDetectedCharset = UNKNOWN_CHARSET, 'Reset kept a charset');
    Check(Prober.GetConfidence = SURE_NO, 'Reset kept confidence');
  finally
    Prober.Free;
  end;
end;

procedure FinalState;
var
  Prober: TSingleUtf8ModelProber;
  Data: AnsiString;
  Returned: eProbingState;
begin
  Data := #$C3#$A9; // UTF-8 U+00E9.
  Prober := TSingleUtf8ModelProber.Create;
  try
    Returned := Prober.HandleData(PAnsiChar(Data), Length(Data));
    Check(Prober.GetState = psFoundIt, 'The only valid model was not selected');
    Check(Returned = Prober.GetState, 'HandleData returned a stale state');
    Check(Prober.GetDetectedCharset = UTF8_CHARSET, 'Wrong UTF-8 identity');
    Prober.Reset;
    Returned := Prober.HandleData(nil, 0);
    Check(Returned = psDetecting, 'An empty block selected a charset');
    Check(Prober.GetDetectedCharset = UNKNOWN_CHARSET, 'Empty data produced evidence');
  finally
    Prober.Free;
  end;
end;

procedure UnicodeAlignment;
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
      if Endian = 0 then
      begin
        Data := 'A'#0'B'#0#$E9#0'-'#0#13#0#10#0;
        Expected := UTF16_LE_CHARSET;
      end
      else
      begin
        Data := #0'A'#0'B'#0#$E9#0'-'#0#13#0#10;
        Expected := UTF16_BE_CHARSET;
      end;
      for Split := 0 to Length(Data) do
      begin
        Prober.Reset;
        Prober.HandleData(PAnsiChar(Data), Split);
        Prober.HandleData(PAnsiChar(Data) + Split, Length(Data) - Split);
        Check(Prober.GetConfidence >= SHORTCUT_THRESHOLD,
          Format('UTF-16 evidence lost: endian=%d split=%d', [Endian, Split]));
        Check(Prober.GetDetectedCharset = Expected,
          Format('UTF-16 alignment lost: endian=%d split=%d', [Endian, Split]));
      end;
    end;
  finally
    Prober.Free;
  end;
end;

procedure HighByte80;
var
  Data, Expected: AnsiString;
  Buffer: array[0..31] of AnsiChar;
  Output: PAnsiChar;
  Count, I: Integer;
begin
  Data := 'abc A'#$80'B xyz';
  Expected := 'A'#$80'B ';
  FillChar(Buffer, SizeOf(Buffer), $CC);
  Output := @Buffer[0];
  Check(FilterWithoutEnglishLetters(PAnsiChar(Data), Length(Data), Output, Count),
    'Filter failed');
  Check(Count = Length(Expected), 'Word containing byte 80 was discarded');
  for I := 0 to Count - 1 do
    Check(Byte(Output[I]) = Byte(Expected[I + 1]), 'Wrong filtered byte');
  Check(Byte(Buffer[Count]) = $CC, 'Filter wrote outside the result');
end;

procedure Utf16CharacterLength;
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
      Check(Machine.GetCurrentCharLen = 2,
        Format('UTF-16LE length is not two for first byte %.2x', [B]));
    end;
  finally
    Machine.Free;
  end;
end;

procedure SingleByteStreaming;
const
  Chunks: array[0..5] of Integer = (1, 2, 3, 7, 64, 8192);
var
  Stream: TFileStream;
  Prober: TnsSBCSGroupProber;
  Data: AnsiString;
  CorpusDir: string;
  Index, Offset, Count: Integer;
  WholeConfidence, Confidence: Double;
begin
  CorpusDir := ParamStr(1);
  if CorpusDir = '' then
    CorpusDir := 'tests/corpus/data';
  Stream := TFileStream.Create(IncludeTrailingPathDelimiter(CorpusDir) +
    'windows-1251.txt', fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Data, Stream.Size);
    Check(Length(Data) > 1024, 'The corpus fixture does not reach the old shortcut');
    Stream.ReadBuffer(Data[1], Length(Data));
  finally
    Stream.Free;
  end;
  Prober := TnsSBCSGroupProber.Create;
  try
    Prober.HandleData(PAnsiChar(Data), Length(Data));
    WholeConfidence := Prober.GetConfidence;
    Check(Prober.GetDetectedCharset = WINDOWS_1251_CHARSET,
      'Whole Windows-1251 corpus was not recognized');
    for Index := Low(Chunks) to High(Chunks) do
    begin
      Prober.Reset;
      Offset := 0;
      while Offset < Length(Data) do
      begin
        Count := Length(Data) - Offset;
        if Count > Chunks[Index] then
          Count := Chunks[Index];
        Prober.HandleData(PAnsiChar(Data) + Offset, Count);
        Inc(Offset, Count);
      end;
      Confidence := Prober.GetConfidence;
      Check(Prober.GetDetectedCharset = WINDOWS_1251_CHARSET,
        Format('Chunk size %d changed the charset', [Chunks[Index]]));
      Check(Confidence = WholeConfidence,
        Format('Chunk size %d changed the complete-input score', [Chunks[Index]]));
    end;
  finally
    Prober.Free;
  end;
end;

procedure ConfidenceSaturation;
var
  Prober: TSingleByteConfidenceProbe;
  Lower, Higher: Double;
begin
  // A protected seam sets attainable counters. The production score method
  // and the original Russian language model remain unchanged.
  Prober := TSingleByteConfidenceProbe.Create(Win1251Model);
  try
    Prober.SetSequenceCounts(970, 1000);
    Lower := Prober.GetConfidence;
    Prober.SetSequenceCounts(990, 1000);
    Higher := Prober.GetConfidence;
    Check(Higher >= Lower, 'More positive evidence lowered confidence');
    Check(Lower <= SURE_YES, 'Confidence exceeded its saturation ceiling');
    Check(Higher = SURE_YES, 'Saturation has the wrong ceiling');
  finally
    Prober.Free;
  end;
end;

procedure JapaneseIncompleteTails;
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
      Lead := #$82;
      Tails := #$A0;
      Hiragana := #$82#$A0;
    end
    else
    begin
      Analysis := TEUCJPContextAnalysis.Create;
      Lead := #$8F;
      Tails := #$A2#$AF;
      Hiragana := #$A4#$A2;
    end;
    try
      Analysis.HandleData(PAnsiChar(Lead), Length(Lead));
      for I := 1 to Length(Tails) do
        Analysis.HandleData(PAnsiChar(Tails) + I - 1, 1);
      for I := 1 to 8 do
        Analysis.HandleData(PAnsiChar(Hiragana), Length(Hiragana));
      Check(Analysis.GetConfidence = 1.0,
        Analysis.ClassName + ': an already consumed tail still skips later bytes');
      Analysis.Reset;
      for I := 1 to 8 do
        Analysis.HandleOneChar(PAnsiChar(Hiragana), Length(Hiragana));
      Check(Analysis.GetConfidence = 1.0,
        Analysis.ClassName + ': complete hiragana pairs lost their positive category');
    finally
      Analysis.Free;
    end;
  end;
end;

procedure JapaneseBoundedInput;
var
  Region: Pointer;
  Lead: PAnsiChar;
  PageSize, Kind, I: Integer;
  Analysis: TJapaneseContextAnalysis;
  Hiragana: AnsiString;
begin
  PageSize := getpagesize;
  Check(PageSize > 0, 'getpagesize failed');
  // Linux: private anonymous read/write mapping, followed by an inaccessible
  // page. This is the equivalent of the Delphi fixture's VirtualProtect case.
  Region := mmap(nil, NativeUInt(PageSize) * 2, 3, $22, -1, 0);
  Check(NativeUInt(Region) <> High(NativeUInt), 'mmap failed');
  try
    Check(mprotect(PAnsiChar(Region) + PageSize, PageSize, 0) = 0,
      'mprotect failed');
    Lead := PAnsiChar(Region) + PageSize - 1;
    for Kind := 0 to 1 do
    begin
      if Kind = 0 then
      begin
        Analysis := TSJISContextAnalysis.Create;
        Lead^ := #$82;
        Hiragana := #$82#$A0;
      end
      else
      begin
        Analysis := TEUCJPContextAnalysis.Create;
        Lead^ := #$A4;
        Hiragana := #$A4#$A2;
      end;
      try
        // No local exception handler: an out-of-bounds access fails this test.
        Analysis.HandleData(Lead, 1);
        Check(Analysis.GetConfidence = -1.0, 'An incomplete character supplied evidence');
        Analysis.HandleData(PAnsiChar(Hiragana) + 1, 1);
        for I := 1 to 8 do
          Analysis.HandleData(PAnsiChar(Hiragana), Length(Hiragana));
        Check(Analysis.GetConfidence = 1.0,
          'Valid characters after a split character were not counted');
      finally
        Analysis.Free;
      end;
    end;
  finally
    munmap(Region, NativeUInt(PageSize) * 2);
  end;
end;

begin
  Run('GB18030 confidence preserves charset and reset', Gb18030Confidence);
  Run('MultiModel HandleData returns final state', FinalState);
  Run('Unicode prober retains every byte at every split', UnicodeAlignment);
  Run('Single-byte filter retains byte 80 and word boundaries', HighByte80);
  Run('UTF-16LE model has two-byte character lengths', Utf16CharacterLength);
  Run('Single-byte scores consume the complete corpus at every chunk size', SingleByteStreaming);
  Run('Single-byte confidence saturation is monotonic', ConfidenceSaturation);
  Run('Japanese context consumes incomplete tails exactly once', JapaneseIncompleteTails);
  Run('Japanese context reads only the supplied bytes', JapaneseBoundedInput);
  Writeln('Prober cases: ', TestsRun - Failures, '/', TestsRun);
  if Failures <> 0 then
    ExitCode := 1;
end.
