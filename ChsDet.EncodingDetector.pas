unit ChsDet.EncodingDetector;

interface

uses
  System.Classes, System.SysUtils,
	
  nsCore, nsUniversalDetector;

type
  TChsDetectionResult = record
    Name: string;
    CodePage: Integer;
    Language: string;
    Confidence: Double;
    BomKind: eBOMKind;
    function HasBom: Boolean;
    function IsUnknown: Boolean;
    function GetEncoding(out AEncoding: TEncoding): Boolean;
    function GetEncodingDef(const ADefault: TEncoding = nil): TEncoding;
  end;

  IChsEncodingDetector = interface
    ['{321D0DE2-01C0-4D3A-9A4B-C3647A22AA57}']
    procedure Reset;
    procedure DisableCodePage(const CodePage: Integer);
    procedure Feed(const Buffer; Count: Integer); overload;
    procedure Feed(const Bytes: TBytes); overload;
    procedure Feed(const Bytes: TBytes; Offset, Count: Integer); overload;
    function Finish: TChsDetectionResult;
    function IsDone: Boolean;
  end;

  TChsEncodingDetector = class(TInterfacedObject, IChsEncodingDetector)
  private
    FDetector: TnsUniversalDetector;
    function BuildResult: TChsDetectionResult;
    class function BytesToPointer(const Bytes: TBytes; Offset: Integer): PAnsiChar; static;
    class function PAnsiCharToString(const Value: PAnsiChar): string; static;
  public
    constructor Create;
    destructor Destroy; override;

    class function New: IChsEncodingDetector; static;
    class function Detect(const Bytes: TBytes): TChsDetectionResult; overload; static;
    class function Detect(const Stream: TStream; ChunkSize: Integer = 8192): TChsDetectionResult; overload; static;
    class function DetectFile(const FileName: string; ChunkSize: Integer = 8192): TChsDetectionResult; static;

    procedure Reset;
    procedure DisableCodePage(const CodePage: Integer);
    procedure Feed(const Buffer; Count: Integer); overload;
    procedure Feed(const Bytes: TBytes); overload;
    procedure Feed(const Bytes: TBytes; Offset, Count: Integer); overload;
    function Finish: TChsDetectionResult;
    function IsDone: Boolean;
  end;

implementation

{ TChsDetectionResult }

function TChsDetectionResult.HasBom: Boolean;
begin
  Result := BomKind <> BOM_Not_Found;
end;

function TChsDetectionResult.IsUnknown: Boolean;
begin
  Result := CodePage < 0;
end;

function TChsDetectionResult.GetEncoding(out AEncoding: TEncoding): Boolean;
begin
  AEncoding := nil;
  Result := False;

  if CodePage <= 0 then
    Exit;

  try
    AEncoding := TEncoding.GetEncoding(CodePage);
    Result := AEncoding <> nil;
  except
    AEncoding := nil;
  end;
end;

function TChsDetectionResult.GetEncodingDef(const ADefault: TEncoding): TEncoding;
begin
  if not GetEncoding(Result) then
  begin
    if ADefault <> nil then
      Result := ADefault
    else
      Result := TEncoding.Default;
  end;
end;

{ TChsEncodingDetector }

constructor TChsEncodingDetector.Create;
begin
  inherited Create;
  FDetector := TnsUniversalDetector.Create;
end;

destructor TChsEncodingDetector.Destroy;
begin
  FDetector.Free;
  inherited Destroy;
end;

function TChsEncodingDetector.BuildResult: TChsDetectionResult;
var
  Info: rCharsetInfo;
begin
  Info := FDetector.GetDetectedCharsetInfo;
  Result.Name := PAnsiCharToString(Info.Name);
  Result.CodePage := Info.CodePage;
  Result.Language := PAnsiCharToString(Info.Language);
  Result.Confidence := FDetector.Confidence;
  Result.BomKind := FDetector.BOMDetected;
end;

class function TChsEncodingDetector.BytesToPointer(const Bytes: TBytes; Offset: Integer): PAnsiChar;
begin
  if Length(Bytes) = 0 then
    Exit(nil);
  Result := PAnsiChar(@Bytes[Offset]);
end;

class function TChsEncodingDetector.PAnsiCharToString(const Value: PAnsiChar): string;
begin
  if Value = nil then
    Exit('');
  Result := string(AnsiString(Value));
end;

class function TChsEncodingDetector.New: IChsEncodingDetector;
begin
  Result := TChsEncodingDetector.Create;
end;

class function TChsEncodingDetector.Detect(const Bytes: TBytes): TChsDetectionResult;
var
  Detector: IChsEncodingDetector;
begin
  Detector := New;
  Detector.Feed(Bytes);
  Result := Detector.Finish;
end;

class function TChsEncodingDetector.Detect(const Stream: TStream; ChunkSize: Integer): TChsDetectionResult;
var
  Detector: IChsEncodingDetector;
  Buffer: TBytes;
  BytesRead: Integer;
begin
  if Stream = nil then
    raise EArgumentNilException.Create('Stream');
  if ChunkSize <= 0 then
    raise EArgumentOutOfRangeException.Create('ChunkSize');

  Detector := New;
  SetLength(Buffer, ChunkSize);

  repeat
    BytesRead := Stream.Read(Buffer[0], Length(Buffer));
    if BytesRead > 0 then
      Detector.Feed(Buffer, 0, BytesRead);
  until (BytesRead = 0) or Detector.IsDone;

  Result := Detector.Finish;
end;

class function TChsEncodingDetector.DetectFile(const FileName: string; ChunkSize: Integer): TChsDetectionResult;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    Result := Detect(Stream, ChunkSize);
  finally
    Stream.Free;
  end;
end;

procedure TChsEncodingDetector.Reset;
begin
  FDetector.Reset;
end;

procedure TChsEncodingDetector.DisableCodePage(const CodePage: Integer);
begin
  FDetector.DisableCharset(CodePage);
end;

procedure TChsEncodingDetector.Feed(const Buffer; Count: Integer);
begin
  if Count < 0 then
    raise EArgumentOutOfRangeException.Create('Count');
  if Count = 0 then
    Exit;
  FDetector.HandleData(PAnsiChar(@Buffer), Count);
end;

procedure TChsEncodingDetector.Feed(const Bytes: TBytes);
begin
  Feed(Bytes, 0, Length(Bytes));
end;

procedure TChsEncodingDetector.Feed(const Bytes: TBytes; Offset, Count: Integer);
begin
  if (Offset < 0) or (Count < 0) or (Offset > Length(Bytes)) or (Offset + Count > Length(Bytes)) then
    raise EArgumentOutOfRangeException.Create('Offset/Count');
  if Count = 0 then
    Exit;
  FDetector.HandleData(BytesToPointer(Bytes, Offset), Count);
end;

function TChsEncodingDetector.Finish: TChsDetectionResult;
begin
  if not FDetector.Done then
    FDetector.DataEnd;
  Result := BuildResult;
end;

function TChsEncodingDetector.IsDone: Boolean;
begin
  Result := FDetector.Done;
end;

end.
