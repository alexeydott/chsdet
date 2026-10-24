program StreamingRegression;

// Supplementary FPC execution of production probers; not a Delphi/DUnitX run.
uses SysUtils, Classes, nsCore, CustomDetector, nsSBCSGroupProber,
  nsLatin1Prober, nsUniversalDetector;

type TCheckProcedure = procedure;
var Passed, Failed, Assertions: Integer;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  Inc(Assertions);
  if not Condition then
    raise Exception.Create(MessageText);
end;

function LoadFixture(const Name: string): RawByteString;
var Stream: TFileStream;
begin
  Stream := TFileStream.Create(IncludeTrailingPathDelimiter(ParamStr(1)) + Name, fmOpenRead);
  try
    SetLength(Result, Stream.Size);
    if Length(Result) > 0 then Stream.ReadBuffer(Result[1], Length(Result));
  finally Stream.Free end;
  Check(Length(Result) > 512, Name + ': insufficient fixture data');
end;

function ByteString(const Values: array of Byte): RawByteString;
begin
  SetLength(Result, Length(Values));
  if Length(Values) > 0 then Move(Values[0], Result[1], Length(Values));
end;

procedure FeedSplit(Probe: TCustomDetector; const Data: RawByteString; Split: Integer);
begin
  if Split > 0 then Probe.HandleData(PAnsiChar(Data), Split);
  if Split < Length(Data) then
    Probe.HandleData(PAnsiChar(Data) + Split, Length(Data) - Split);
end;

procedure SbcsWordBoundariesSurviveEverySplit;
const Names: array[0..1] of string = ('windows-1253-no-c1.txt', 'iso-8859-8.txt');
  CodePages: array[0..1] of Integer = (1253, 28598);
var Probe: TnsSBCSGroupProber; Data: RawByteString;
  ExpectedConfidence, ActualConfidence: Double; I, Split, J: Integer;
begin
  Probe := TnsSBCSGroupProber.Create;
  try
    for I := Low(Names) to High(Names) do
    begin
      Data := Copy(LoadFixture(Names[I]), 1, 512);
      Probe.Reset; Probe.HandleData(PAnsiChar(Data), Length(Data));
      ExpectedConfidence := Probe.GetConfidence;
      Check(KNOWN_CHARSETS[Probe.GetDetectedCharset].CodePage = CodePages[I], Names[I] + ': whole charset');
      Check(ExpectedConfidence > 0.9, Names[I] + ': whole confidence');
      for Split := 0 to Length(Data) do
      begin
        Probe.Reset; FeedSplit(Probe, Data, Split);
        ActualConfidence := Probe.GetConfidence;
        Check(KNOWN_CHARSETS[Probe.GetDetectedCharset].CodePage = CodePages[I], Names[I] + ': split charset ' + IntToStr(Split));
        Check(Abs(ExpectedConfidence - ActualConfidence) < 1E-12, Names[I] + ': split statistics ' + IntToStr(Split));
      end;
      Probe.Reset;
      for J := 1 to Length(Data) do Probe.HandleData(@Data[J], 1);
      ActualConfidence := Probe.GetConfidence;
      Check(KNOWN_CHARSETS[Probe.GetDetectedCharset].CodePage = CodePages[I], Names[I] + ': bytewise charset');
      Check(Abs(ExpectedConfidence - ActualConfidence) < 1E-12, Names[I] + ': bytewise statistics');
    end;
  finally Probe.Free end;
end;

procedure SbcsResetClearsPendingWordState;
var Probe: TnsSBCSGroupProber; Data, Prefix: RawByteString; ExpectedConfidence: Double;
begin
  Data := Copy(LoadFixture('windows-1253-no-c1.txt'), 1, 512);
  Prefix := 'ASCII '; Data := Prefix + Data;
  Prefix := ByteString([$E0]);
  Probe := TnsSBCSGroupProber.Create;
  try
    Probe.HandleData(PAnsiChar(Data), Length(Data)); ExpectedConfidence := Probe.GetConfidence;
    Check(KNOWN_CHARSETS[Probe.GetDetectedCharset].CodePage = 1253, 'whole Greek charset');
    Probe.Reset; Probe.HandleData(PAnsiChar(Prefix), Length(Prefix)); Probe.Reset;
    Probe.HandleData(PAnsiChar(Data), Length(Data));
    Check(Abs(ExpectedConfidence - Probe.GetConfidence) < 1E-12, 'Reset retained a preceding international word');
    Check(KNOWN_CHARSETS[Probe.GetDetectedCharset].CodePage = 1253, 'Greek charset after Reset');
  finally Probe.Free end;
end;

procedure CheckLatin1Splits(const Data: RawByteString);
var Probe: TnsLatin1Prober; Split, I: Integer;
begin
  Check(Length(Data) > 0, 'Nonempty Latin1 fixture');
  Probe := TnsLatin1Prober.Create;
  try
    for Split := 0 to Length(Data) do
    begin
      Probe.Reset; FeedSplit(Probe, Data, Split);
      Check(Probe.GetState = psDetecting, 'Latin1 state at split ' + IntToStr(Split));
      Check(Abs(0.5 - Probe.GetConfidence) < 1E-12, 'Latin1 confidence at split ' + IntToStr(Split));
      Check(KNOWN_CHARSETS[Probe.GetDetectedCharset].CodePage = 1252, 'Latin1 charset');
    end;
    Probe.Reset;
    for I := 1 to Length(Data) do Probe.HandleData(@Data[I], 1);
    Check(Probe.GetState = psDetecting, 'Latin1 bytewise state');
    Check(Abs(0.5 - Probe.GetConfidence) < 1E-12, 'Latin1 bytewise confidence');
  finally Probe.Free end;
end;

procedure Latin1SeparatorsSurviveEverySplit;
begin CheckLatin1Splits(ByteString([$E9, $20, $41, $20, $E9, $20, $42, $20,
  $E9, $20, $43, $20])) end;

procedure Latin1TagsSurviveEverySplit;
begin CheckLatin1Splits(ByteString([$6E, $6F, $72, $6D, $61, $6C, $20, $3C,
  $71, $20, $74, $69, $74, $6C, $65, $3D, $22, $81, $22, $3E, $74, $65,
  $78, $74, $3C, $2F, $71, $3E, $20, $63, $61, $66, $65, $E9, $2E])) end;

procedure Latin1ResetClearsTagStateAndRejectsUndefinedBytes;
var Probe: TnsLatin1Prober; Data: RawByteString;
begin
  Probe := TnsLatin1Prober.Create;
  try
    Data := '<q title="'; Probe.HandleData(PAnsiChar(Data), Length(Data)); Probe.Reset;
    Data := ByteString([$81]);
    Check(Probe.HandleData(PAnsiChar(Data), Length(Data)) = psNotMe, 'Undefined CP1252 byte outside tag must reject');
    Check(Abs(SURE_NO - Probe.GetConfidence) < 1E-12, 'Rejected confidence');
    Probe.Reset; Data := ByteString([$E9, $20, $41, $20]); Probe.HandleData(PAnsiChar(Data), Length(Data));
    Check(Probe.GetState = psDetecting, 'Reset after invalid data');
    Check(Abs(0.5 - Probe.GetConfidence) < 1E-12, 'Reset confidence');
  finally Probe.Free end;
end;

procedure CorpusSingleByteResultsSurviveSmallChunks;
const Names: array[0..2] of string = ('windows-1251.txt', 'windows-1253-no-c1.txt', 'iso-8859-8.txt');
  ExpectedNames: array[0..2] of string = ('windows-1251', 'windows-1253', 'ISO-8859-8');
  CodePages: array[0..2] of Integer = (1251, 1253, 28598);
  Chunks: array[0..4] of Integer = (1, 2, 3, 7, 64);
var Detector: TnsUniversalDetector; Data: RawByteString;
  Actual: rCharsetInfo; I, C, Chunk, Offset, Count: Integer;
begin
  Detector := TnsUniversalDetector.Create;
  try
    for I := Low(Names) to High(Names) do
    begin
      Data := LoadFixture(Names[I]);
      for C := Low(Chunks) to High(Chunks) do
      begin
        Chunk := Chunks[C]; Detector.Reset; Offset := 0;
        while Offset < Length(Data) do
        begin
          Count := Chunk; if Count > Length(Data) - Offset then Count := Length(Data) - Offset;
          Detector.HandleData(PAnsiChar(Data) + Offset, Count); Inc(Offset, Count);
        end;
        Detector.DataEnd; Actual := Detector.GetDetectedCharsetInfo;
        Check(Actual.CodePage = CodePages[I], Names[I] + ': code page chunk ' + IntToStr(Chunk));
        Check(string(Actual.Name) = ExpectedNames[I], Names[I] + ': name chunk ' + IntToStr(Chunk));
        Check(Detector.BOMDetected = BOM_Not_Found, Names[I] + ': unexpected BOM');
      end;
    end;
  finally Detector.Free end;
end;

procedure Run(const Name: string; Test: TCheckProcedure);
var Before: Integer;
begin
  Before := Assertions;
  try
    Test;
    if Assertions = Before then raise Exception.Create('No assertions executed');
    Inc(Passed); Writeln('PASS ', Name, ' assertions=', Assertions - Before);
  except
    on E: Exception do begin Inc(Failed); Writeln('FAIL ', Name, ': ', E.ClassName, ': ', E.Message) end;
  end;
end;

begin
  if ParamCount <> 1 then begin Writeln('Usage: StreamingRegression CORPUS_DATA_DIR'); Halt(2) end;
  Run('SbcsWordBoundariesSurviveEverySplit', SbcsWordBoundariesSurviveEverySplit);
  Run('SbcsResetClearsPendingWordState', SbcsResetClearsPendingWordState);
  Run('Latin1SeparatorsSurviveEverySplit', Latin1SeparatorsSurviveEverySplit);
  Run('Latin1TagsSurviveEverySplit', Latin1TagsSurviveEverySplit);
  Run('Latin1ResetClearsTagStateAndRejectsUndefinedBytes', Latin1ResetClearsTagStateAndRejectsUndefinedBytes);
  Run('CorpusSingleByteResultsSurviveSmallChunks', CorpusSingleByteResultsSurviveSmallChunks);
  Writeln('Executed=', Passed + Failed, ' passed=', Passed, ' failed=', Failed, ' assertions=', Assertions);
  if Failed <> 0 then Halt(1);
end.
