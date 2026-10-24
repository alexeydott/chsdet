program WrapperProbe;

{$APPTYPE CONSOLE}

uses
  SysUtils, nsCore, ChsDet.EncodingDetector;

type
  TTestProc = procedure;

var
  TestsRun, Failures: Integer;

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

procedure OverflowBounds;
var
  Bytes: TBytes;
  Detector: IChsEncodingDetector;
  Rejected: Boolean;
  Detection: TChsDetectionResult;
begin
    SetLength(Bytes, 4);
    Bytes[0] := Ord('t');
    Bytes[1] := Ord('e');
    Bytes[2] := Ord('s');
    Bytes[3] := Ord('t');
    Detector := TChsEncodingDetector.New;
    Rejected := False;
    try
      Detector.Feed(Bytes, 1, MaxInt);
    except
      on E: EArgumentOutOfRangeException do
        Rejected := True;
    end;
    if not Rejected then
      raise Exception.Create('Overflowing Count was not rejected');
    Detector.Feed(Bytes);
    Detection := Detector.Finish;
    if (Detection.CodePage <> 0) or (Detection.Name <> 'ASCII') then
      raise Exception.Create('Rejected Feed changed the detector state');
end;

procedure CheckExoticUcs4Decoder(Index: Integer);
const
  Samples: array[0..1, 0..7] of Byte = (
    ($00, $00, $FF, $FE, $00, $00, $41, $00),
    ($FE, $FF, $00, $00, $00, $41, $00, $00));
  Names: array[0..1] of string = (
    'X-ISO-10646-UCS-4-2143', 'X-ISO-10646-UCS-4-3412');
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
  Encoding: TEncoding;
begin
  SetLength(Bytes, 8);
    Move(Samples[Index, 0], Bytes[0], Length(Bytes));
    Detection := TChsEncodingDetector.Detect(Bytes);
    if Detection.Name <> Names[Index] then
      raise Exception.Create('Exotic UCS-4 BOM not identified');
    Encoding := nil;
    try
      if Detection.GetEncoding(Encoding) then
        raise Exception.Create('Exotic UCS-4 received an incompatible UTF-32 decoder');
      if Encoding <> nil then
        raise Exception.Create('Failed GetEncoding retained a decoder');
    finally
      if (Encoding <> nil) and not TEncoding.IsStandardEncoding(Encoding) then
        Encoding.Free;
    end;
    if Detection.GetEncodingDef(TEncoding.ASCII) <> TEncoding.ASCII then
      raise Exception.Create('Exotic UCS-4 did not preserve explicit fallback');
end;

procedure ExoticUcs42143;
begin
  CheckExoticUcs4Decoder(0);
end;

procedure ExoticUcs43412;
begin
  CheckExoticUcs4Decoder(1);
end;

procedure ResetAfterIncompleteUtf8;
var
  Detector: IChsEncodingDetector;
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  Detector := TChsEncodingDetector.New;
  SetLength(Bytes, 5);
  Bytes[0] := $F0;
  Bytes[1] := $9F;
  Bytes[2] := $99;
  Bytes[3] := $82;
  Bytes[4] := $F0;
  Detector.Feed(Bytes);
  Detection := Detector.Finish;
  if Detection.CodePage = 65001 then
    raise Exception.Create('Incomplete UTF-8 was accepted');
  Detector.Reset;
  SetLength(Bytes, 4);
  Bytes[0] := Ord('t');
  Bytes[1] := Ord('e');
  Bytes[2] := Ord('s');
  Bytes[3] := Ord('t');
  Detector.Feed(Bytes);
  Detection := Detector.Finish;
  if (Detection.CodePage <> 0) or (Detection.Name <> 'ASCII') then
    raise Exception.Create('Reset retained invalid UTF-8 state');
  if Detection.HasBom then
    raise Exception.Create('Reset retained a BOM');
end;

procedure EucTwCodePage;
begin
  // Windows' EUC-TW identifier is 51950; 51936 identifies EUC-CN.
  if KNOWN_CHARSETS[X_EUC_TW_CHARSET].CodePage <> 51950 then
    raise Exception.Create('EUC-TW has the EUC-CN code page');
  if string(AnsiString(KNOWN_CHARSETS[X_EUC_TW_CHARSET].Name)) <> 'x-euc-tw' then
    raise Exception.Create('EUC-TW identity changed');
end;

procedure FinishIsTerminalUntilReset;
var
  Detector: IChsEncodingDetector;
  Bytes: TBytes;
  Detection, Repeated: TChsDetectionResult;
begin
  Detector := TChsEncodingDetector.New;
  if Detector.IsDone then
    raise Exception.Create('A new detector is already done');
  Detection := Detector.Finish;
  if not Detection.IsUnknown then
    raise Exception.Create('Empty input produced a charset');
  if not Detector.IsDone then
    raise Exception.Create('Finish did not finalize empty input');
  SetLength(Bytes, 4);
  Bytes[0] := Ord('t');
  Bytes[1] := Ord('e');
  Bytes[2] := Ord('s');
  Bytes[3] := Ord('t');
  Detector.Feed(Bytes);
  Repeated := Detector.Finish;
  if (Repeated.CodePage <> Detection.CodePage) or
     (Repeated.Name <> Detection.Name) or
     (Repeated.Confidence <> Detection.Confidence) or
     (Repeated.BomKind <> Detection.BomKind) then
    raise Exception.Create('Feed changed a finalized result');
  Detector.Reset;
  if Detector.IsDone then
    raise Exception.Create('Reset did not reopen the detector');
  Detector.Feed(Bytes);
  Detection := Detector.Finish;
  if (Detection.CodePage <> 0) or (Detection.Name <> 'ASCII') then
    raise Exception.Create('ASCII after reset was not detected');
  if not Detector.IsDone then
    raise Exception.Create('Finish did not finalize ASCII input');
  Repeated := Detector.Finish;
  if (Repeated.CodePage <> Detection.CodePage) or
     (Repeated.Name <> Detection.Name) or
     (Repeated.Confidence <> Detection.Confidence) then
    raise Exception.Create('Repeated Finish changed the result');
end;

procedure WholeMixedWordPreservesCyrillicEvidence;
const
  Sample: array[0..21] of Byte = (
    $74, $65, $73, $74, $CE, $F1, $F2, $E0, $ED, $EE, $E2,
    $EA, $E0, $20, $E0, $E2, $F2, $EE, $E1, $F3, $F1, $E0);
var
  Bytes: TBytes;
  Detection: TChsDetectionResult;
begin
  SetLength(Bytes, Length(Sample));
  Move(Sample[0], Bytes[0], Length(Sample));
  Detection := TChsEncodingDetector.Detect(Bytes);
  if (Detection.CodePage <> 1251) or (Detection.Name <> 'windows-1251') then
    raise Exception.Create('BOM prefix replay changed the intact Windows-1251 word');
end;

begin
  Run('overflow-safe bounds and state preservation', OverflowBounds);
  Run('UCS-4 2143 decoder refusal and explicit fallback', ExoticUcs42143);
  Run('UCS-4 3412 decoder refusal and explicit fallback', ExoticUcs43412);
  Run('valid ASCII after reset of incomplete UTF-8', ResetAfterIncompleteUtf8);
  Run('EUC-TW Windows code-page mapping', EucTwCodePage);
  Run('Finish is terminal until Reset, including empty input', FinishIsTerminalUntilReset);
  Run('Whole mixed ASCII/Cyrillic word retains Windows-1251 evidence', WholeMixedWordPreservesCyrillicEvidence);
  Writeln('Wrapper cases: ', TestsRun - Failures, '/', TestsRun);
  if Failures <> 0 then
    ExitCode := 1;
end.
