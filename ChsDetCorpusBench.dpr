program ChsDetCorpusBench;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  ChsDet.Corpus in 'tests\ChsDet.Corpus.pas',
  ChsDet.EncodingDetector in 'ChsDet.EncodingDetector.pas',
  ChsDet.Fluent in 'ChsDet.Fluent.pas',
  nsCore in 'nsCore.pas',
  nsUniversalDetector in 'nsUniversalDetector.pas',
  CustomDetector in 'CustomDetector.pas',
  nsGroupProber in 'nsGroupProber.pas',
  nsMBCSMultiProber in 'nsMBCSMultiProber.pas',
  nsSBCSGroupProber in 'nsSBCSGroupProber.pas',
  nsEscCharsetProber in 'nsEscCharsetProber.pas',
  nsLatin1Prober in 'nsLatin1Prober.pas',
  nsUTF8Prober in 'nsUTF8Prober.pas',
  MBUnicodeMultiProber in 'MBUnicodeMultiProber.pas',
  MultiModelProber in 'MultiModelProber.pas',
  nsCodingStateMachine in 'nsCodingStateMachine.pas',
  CharDistribution in 'CharDistribution.pas',
  JpCntx in 'JpCntx.pas',
  nsSBCharSetProber in 'nsSBCharSetProber.pas',
  nsHebrewProber in 'nsHebrewProber.pas',
  LangCyrillicModel in 'LangCyrillicModel.pas',
  LangGreekModel in 'LangGreekModel.pas',
  LangBulgarianModel in 'LangBulgarianModel.pas',
  LangHebrewModel in 'LangHebrewModel.pas',
  Big5Freq in 'Big5Freq.pas',
  EUCKRFreq in 'EUCKRFreq.pas',
  EUCTWFreq in 'EUCTWFreq.pas',
  GB2312Freq in 'GB2312Freq.pas',
  JISFreq in 'JISFreq.pas';

var
  Results: TArray<TChsCorpusResult>;
  Matrix: string;
  Failures: Integer;
begin
  try
    Results := TChsCorpus.RunAll;
    Matrix := TChsCorpus.BuildMarkdownMatrix(Results);
    TFile.WriteAllText(TChsCorpus.MatrixPath, Matrix, TEncoding.UTF8);

    Failures := TChsCorpus.StrictFailureCount(Results);
    Writeln(Matrix);
    Writeln;
    Writeln('Matrix written to: ', TChsCorpus.MatrixPath);
    Writeln('Strict failures: ', Failures);

    if Failures <> 0 then
      ExitCode := 1;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
