unit ChsDet.Fluent;

interface

uses
  System.Classes, System.SysUtils,
  ChsDet.EncodingDetector;

type
	TChsDetectionResult = ChsDet.EncodingDetector.TChsDetectionResult;
	
  IChsFluentDetector = interface
    ['{D7E6293D-2E36-45CC-A10C-AE2DC3C78B19}']
    function Reset: IChsFluentDetector;
    function DisableCodePage(const CodePage: Integer): IChsFluentDetector;
    function DisableCodePages(const CodePages: array of Integer): IChsFluentDetector;
    function Feed(const Buffer; Count: Integer): IChsFluentDetector; overload;
    function Feed(const Bytes: TBytes): IChsFluentDetector; overload;
    function Feed(const Bytes: TBytes; Offset, Count: Integer): IChsFluentDetector; overload;
    function Feed(const Stream: TStream; ChunkSize: Integer = 8192): IChsFluentDetector; overload;
    function FeedFile(const FileName: string; ChunkSize: Integer = 8192): IChsFluentDetector;
    function Detect: TChsDetectionResult;
    function IsDone: Boolean;
  end;

  TChsDetect = record
  public
    class function New: IChsFluentDetector; static;
    class function From(const Bytes: TBytes): IChsFluentDetector; overload; static;
    class function From(const Stream: TStream; ChunkSize: Integer = 8192): IChsFluentDetector; overload; static;
    class function FromFile(const FileName: string; ChunkSize: Integer = 8192): IChsFluentDetector; static;
    class function Detect(const Bytes: TBytes): TChsDetectionResult; overload; static;
    class function Detect(const Stream: TStream; ChunkSize: Integer = 8192): TChsDetectionResult; overload; static;
    class function DetectFile(const FileName: string; ChunkSize: Integer = 8192): TChsDetectionResult; static;
  end;

implementation

type
  TChsFluentDetector = class(TInterfacedObject, IChsFluentDetector)
  private
    FInner: IChsEncodingDetector;
    class procedure ValidateChunkSize(const ChunkSize: Integer); static;
  public
    constructor Create;

    function Reset: IChsFluentDetector;
    function DisableCodePage(const CodePage: Integer): IChsFluentDetector;
    function DisableCodePages(const CodePages: array of Integer): IChsFluentDetector;
    function Feed(const Buffer; Count: Integer): IChsFluentDetector; overload;
    function Feed(const Bytes: TBytes): IChsFluentDetector; overload;
    function Feed(const Bytes: TBytes; Offset, Count: Integer): IChsFluentDetector; overload;
    function Feed(const Stream: TStream; ChunkSize: Integer = 8192): IChsFluentDetector; overload;
    function FeedFile(const FileName: string; ChunkSize: Integer = 8192): IChsFluentDetector;
    function Detect: TChsDetectionResult;
    function IsDone: Boolean;
  end;

{ TChsFluentDetector }

constructor TChsFluentDetector.Create;
begin
  inherited Create;
  FInner := TChsEncodingDetector.New;
end;

class procedure TChsFluentDetector.ValidateChunkSize(const ChunkSize: Integer);
begin
  if ChunkSize <= 0 then
    raise EArgumentOutOfRangeException.Create('ChunkSize');
end;

function TChsFluentDetector.Reset: IChsFluentDetector;
begin
  FInner.Reset;
  Result := Self;
end;

function TChsFluentDetector.DisableCodePage(const CodePage: Integer): IChsFluentDetector;
begin
  FInner.DisableCodePage(CodePage);
  Result := Self;
end;

function TChsFluentDetector.DisableCodePages(const CodePages: array of Integer): IChsFluentDetector;
var
  CodePage: Integer;
begin
  for CodePage in CodePages do
    FInner.DisableCodePage(CodePage);
  Result := Self;
end;

function TChsFluentDetector.Feed(const Buffer; Count: Integer): IChsFluentDetector;
begin
  FInner.Feed(Buffer, Count);
  Result := Self;
end;

function TChsFluentDetector.Feed(const Bytes: TBytes): IChsFluentDetector;
begin
  FInner.Feed(Bytes);
  Result := Self;
end;

function TChsFluentDetector.Feed(const Bytes: TBytes; Offset, Count: Integer): IChsFluentDetector;
begin
  FInner.Feed(Bytes, Offset, Count);
  Result := Self;
end;

function TChsFluentDetector.Feed(const Stream: TStream; ChunkSize: Integer): IChsFluentDetector;
var
  Buffer: TBytes;
  BytesRead: Integer;
begin
  if Stream = nil then
    raise EArgumentNilException.Create('Stream');

  ValidateChunkSize(ChunkSize);
  SetLength(Buffer, ChunkSize);

  repeat
    BytesRead := Stream.Read(Buffer[0], Length(Buffer));
    if BytesRead > 0 then
      FInner.Feed(Buffer, 0, BytesRead);
  until (BytesRead = 0) or FInner.IsDone;

  Result := Self;
end;

function TChsFluentDetector.FeedFile(const FileName: string; ChunkSize: Integer): IChsFluentDetector;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    Result := Feed(Stream, ChunkSize);
  finally
    Stream.Free;
  end;
end;

function TChsFluentDetector.Detect: TChsDetectionResult;
begin
  Result := FInner.Finish;
end;

function TChsFluentDetector.IsDone: Boolean;
begin
  Result := FInner.IsDone;
end;

{ TChsDetect }

class function TChsDetect.New: IChsFluentDetector;
begin
  Result := TChsFluentDetector.Create;
end;

class function TChsDetect.From(const Bytes: TBytes): IChsFluentDetector;
begin
  Result := New.Feed(Bytes);
end;

class function TChsDetect.From(const Stream: TStream; ChunkSize: Integer): IChsFluentDetector;
begin
  Result := New.Feed(Stream, ChunkSize);
end;

class function TChsDetect.FromFile(const FileName: string; ChunkSize: Integer): IChsFluentDetector;
begin
  Result := New.FeedFile(FileName, ChunkSize);
end;

class function TChsDetect.Detect(const Bytes: TBytes): TChsDetectionResult;
begin
  Result := From(Bytes).Detect;
end;

class function TChsDetect.Detect(const Stream: TStream; ChunkSize: Integer): TChsDetectionResult;
begin
  Result := From(Stream, ChunkSize).Detect;
end;

class function TChsDetect.DetectFile(const FileName: string; ChunkSize: Integer): TChsDetectionResult;
begin
  Result := FromFile(FileName, ChunkSize).Detect;
end;

end.
