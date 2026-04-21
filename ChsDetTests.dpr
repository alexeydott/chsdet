program ChsDetTests;

{$APPTYPE CONSOLE}

uses
  DUnitX.Loggers.Console,
  DUnitX.Loggers.XML.NUnit,
  DUnitX.RunResults,
  DUnitX.TestFramework,
  DUnitX.TestRunner,
  System.SysUtils,
  ChsDet.Corpus in 'tests\ChsDet.Corpus.pas',
  ChsDet.Tests in 'tests\ChsDet.Tests.pas',
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
  Runner: ITestRunner;
  Results: IRunResults;
begin
  try
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := True;
    Runner.AddLogger(TDUnitXConsoleLogger.Create(True));
    Runner.AddLogger(TDUnitXXMLNUnitFileLogger.Create);

    Results := Runner.Execute;
    if not Results.AllPassed then
      ExitCode := 1;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
