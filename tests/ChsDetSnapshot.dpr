program ChsDetSnapshot;

{$APPTYPE CONSOLE}

uses
  System.Classes, System.SysUtils, System.IOUtils,
  ChsDet.Corpus in 'ChsDet.Corpus.pas',
  ChsDet.EncodingDetector;

var
  Cases: TArray<TChsCorpusCase>;
  Item: TChsCorpusCase;
  Detection: TChsDetectionResult;
  Lines: TStringList;
  Bits: UInt64;
begin
  try
    if ParamCount <> 1 then
      raise Exception.Create('Usage: ChsDetSnapshot output.tsv');
    Cases := TChsCorpus.LoadCases;
    if Length(Cases) = 0 then
      raise Exception.Create('Empty corpus');
    Lines := TStringList.Create;
    try
      Lines.Add('file'#9'name'#9'codepage'#9'language'#9'confidence-bits'#9'bom');
      for Item in Cases do
      begin
        Detection := TChsEncodingDetector.DetectFile(TPath.Combine(TChsCorpus.DataDir, Item.FileName));
        Move(Detection.Confidence, Bits, SizeOf(Bits));
        Lines.Add(Item.FileName + #9 + Detection.Name + #9 + IntToStr(Detection.CodePage) + #9 +
          Detection.Language + #9 + IntToHex(Bits, 16) + #9 + IntToStr(Ord(Detection.BomKind)));
      end;
      Lines.SaveToFile(ParamStr(1), TEncoding.UTF8);
    finally
      Lines.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
