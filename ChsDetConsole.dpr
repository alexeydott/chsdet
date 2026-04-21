program ChsDetConsole;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  ChsDet.Fluent in 'ChsDet.Fluent.pas',
  ChsDet.EncodingDetector in 'ChsDet.EncodingDetector.pas',
  nsCore in 'nsCore.pas';

function BomToString(BomKind: eBOMKind): string;
begin
  case BomKind of
    BOM_Not_Found:
      Result := 'none';
    BOM_UCS4_BE:
      Result := 'ucs4-be';
    BOM_UCS4_LE:
      Result := 'ucs4-le';
    BOM_UCS4_2143:
      Result := 'ucs4-2143';
    BOM_UCS4_3412:
      Result := 'ucs4-3412';
    BOM_UTF16_BE:
      Result := 'utf16-be';
    BOM_UTF16_LE:
      Result := 'utf16-le';
    BOM_UTF8:
      Result := 'utf8';
  else
    Result := 'unknown';
  end;
end;

procedure Run;
var
  Detection: TChsDetectionResult;
begin
  if ParamCount < 1 then
    raise Exception.Create('Usage: ChsDetConsole <file>');

  Detection := TChsDetect.New
    .FeedFile(ParamStr(1))
    .Detect;

  Writeln('File: ', ParamStr(1));
  Writeln('Charset: ', Detection.Name);
  Writeln('CodePage: ', Detection.CodePage);
  Writeln('Language: ', Detection.Language);
  Writeln(Format('Confidence: %.4f', [Detection.Confidence]));
  Writeln('BOM: ', BomToString(Detection.BomKind));
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
