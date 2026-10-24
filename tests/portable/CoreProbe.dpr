program CoreProbe;

{$APPTYPE CONSOLE}

uses
  SysUtils, Classes, nsCore, nsUniversalDetector;

var
  Detector: TnsUniversalDetector;
  Input: TFileStream;
  Data: RawByteString;
  Info: rCharsetInfo;
  ChunkSize, Offset, Count: Integer;
begin
  try
    if ParamCount < 1 then
      raise Exception.Create('Usage: CoreProbe FILE [CHUNK_SIZE] [DISABLED_CODEPAGE]');
    Input := TFileStream.Create(ParamStr(1), fmOpenRead or fmShareDenyWrite);
    try
      if Input.Size > MaxInt then
        raise Exception.Create('Fixture exceeds Integer API capacity');
      SetLength(Data, Integer(Input.Size));
      if Length(Data) > 0 then
        Input.ReadBuffer(Data[1], Length(Data));
    finally
      Input.Free;
    end;
    ChunkSize := StrToIntDef(ParamStr(2), Length(Data));
    if ChunkSize <= 0 then
      ChunkSize := Length(Data);
    if ChunkSize = 0 then
      ChunkSize := 1;
    Detector := TnsUniversalDetector.Create;
    try
      if ParamCount >= 3 then
        Detector.DisableCharset(StrToInt(ParamStr(3)));
      Offset := 1;
      while Offset <= Length(Data) do
      begin
        Count := Length(Data) - Offset + 1;
        if Count > ChunkSize then
          Count := ChunkSize;
        Detector.HandleData(@Data[Offset], Count);
        Inc(Offset, Count);
      end;
      Detector.DataEnd;
      Info := Detector.GetDetectedCharsetInfo;
      Writeln(Info.CodePage, #9, Info.Name, #9, Info.Language, #9,
        Detector.Confidence:0:12, #9, Ord(Detector.BOMDetected));
    finally
      Detector.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
