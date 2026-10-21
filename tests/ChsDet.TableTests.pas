unit ChsDet.TableTests;

interface

uses DUnitX.TestFramework, nsCore, nsCodingStateMachine;

type
  [TestFixture]
  TChsTableTests = class
  private
    procedure CheckModel(const Name: string; const Model: SMModel;
      const Classes, States: array of Byte);
  public
    [Test] procedure AllReachableTransitionsStayInsideLiteralTables;
    [Test] procedure RawTablesDoNotRequireDynamicArrayHeaders;
    [Test] procedure PackedNibblesIncludeHighBitAndWordBoundary;
    [Test] procedure DistributionChecksActualLengthBeforeReading;
  end;

implementation

uses System.SysUtils, nsPkg, CharDistribution;

{$I '../Big5LangModel.inc'}
{$I '../EUCJPLangModel.inc'}
{$I '../EUCKRLangModel.inc'}
{$I '../EUCTWLangModel.inc'}
{$I '../GB18030LangModel.inc'}
{$I '../HZLangModel.inc'}
{$I '../ISO2022CNLangModel.inc'}
{$I '../ISO2022JPLangModel.inc'}
{$I '../ISO2022KRLangModel.inc'}
{$I '../SJISLangModel.inc'}
{$I '../UCS2BELangModel.inc'}
{$I '../UCS2LELangModel.inc'}
{$I '../UTF8LangModel.inc'}

type
  // Legal protected seam, never a layout cast of an unrelated object.
  TMachineProbe = class(TnsCodingStateMachine)
    procedure SetState(Value: Integer);
  end;

  TDistributionProbe = class(TCharDistributionAnalysis)
  private
    FOrder: Integer;
  protected
    function GetOrder(Str: PAnsiChar): PRInt32; override;
  public
    procedure Configure(Table: pPRInt16; Count: Integer);
    procedure FeedOrder(Value: Integer);
    function Frequent: Cardinal;
    function Total: Cardinal;
  end;

procedure TMachineProbe.SetState(Value: Integer);
begin
  mCurrentState := nsSMState(Value);
  mCurrentBytePos := 0;
end;

procedure TChsTableTests.CheckModel(const Name: string; const Model: SMModel;
  const Classes, States: array of Byte);
var
  Seen: array [0..255] of Boolean;
  Queue: array [0..255] of Integer;
  Head, Tail, State, B, Cls, Index, Expected: Integer;
  Machine: TMachineProbe;
begin
  Assert.AreEqual<Integer>(256, Length(Classes), Name);
  FillChar(Seen, SizeOf(Seen), 0);
  Head := 0;
  Tail := 1;
  Queue[0] := 0;
  Seen[0] := True;
  Machine := TMachineProbe.Create(Model);
  try
    while Head < Tail do
    begin
      State := Queue[Head];
      Inc(Head);
      for B := 0 to 255 do
      begin
        Cls := Classes[B];
        Assert.IsTrue(Cls < Integer(Model.classFactor), Name + ': class');
        Index := State * Integer(Model.classFactor) + Cls;
        Assert.IsTrue((Index >= 0) and (Index < Length(States)), Name + ': state index');
        Expected := States[Index];
        Machine.SetState(State);
        Assert.AreEqual<Integer>(Expected, Ord(Machine.NextState(AnsiChar(B))),
          Format('%s state=%d byte=%d', [Name, State, B]));
        if not Seen[Expected] then
        begin
          Seen[Expected] := True;
          Queue[Tail] := Expected;
          Inc(Tail);
        end;
      end;
    end;
    Machine.Reset;
    Machine.Enabled := False;
    Assert.AreEqual<Integer>(Ord(eError), Ord(Machine.NextState('A')));
    Machine.Enabled := True;
    Assert.AreEqual<Integer>(States[Classes[65]], Ord(Machine.NextState('A')));
  finally
    Machine.Free;
  end;
end;

procedure TChsTableTests.AllReachableTransitionsStayInsideLiteralTables;
begin
  CheckModel('Big5LangModel', Big5LangModel, BIG5_cls, BIG5_st);
  CheckModel('EUCJPLangModel', EUCJPLangModel, EUCJP_cls, EUCJP_st);
  CheckModel('EUCKRLangModel', EUCKRLangModel, EUCKR_cls, EUCKR_st);
  CheckModel('EUCTWLangModel', EUCTWLangModel, EUCTW_cls, EUCTW_st);
  CheckModel('GB18030LangModel', GB18030LangModel, GB18030_cls, GB18030_st);
  CheckModel('HZLangModel', HZSMModel, HZ_cls, HZ_st);
  CheckModel('ISO2022CNLangModel', ISO2022CNSMModel, ISO2022CN_cls, ISO2022CN_st);
  CheckModel('ISO2022JPLangModel', ISO2022JPSMModel, ISO2022JP_cls, ISO2022JP_st);
  CheckModel('ISO2022KRLangModel', ISO2022KRSMModel, ISO2022KR_cls, ISO2022KR_st);
  CheckModel('SJISLangModel', SJISLangModel, SJIS_cls, SJIS_st);
  CheckModel('UCS2BELangModel', UCS2BELangModel, UCS2BE_cls, UCS2BE_st);
  CheckModel('UCS2LELangModel', UCS2LELangModel, UCS2LE_cls, UCS2LE_st);
  CheckModel('UTF8LangModel', UTF8LangModel, UTF8_cls, UTF8_st);
end;

procedure TChsTableTests.RawTablesDoNotRequireDynamicArrayHeaders;
var
  // Zero bytes immediately before each payload make old dynamic-array casts
  // reliably fail under R+ on both 32- and 64-bit Delphi (length = zero).
  Classes: packed record Header: UInt64; Data: array [0..255] of Byte; end;
  States: packed record Header: UInt64; Data: array [0..2] of Byte; end;
  Lens: packed record Header: UInt64; Data: array [0..0] of Byte; end;
  Model: SMModel;
  Machine: TnsCodingStateMachine;
begin
  FillChar(Classes, SizeOf(Classes), 0);
  FillChar(States, SizeOf(States), 0);
  FillChar(Lens, SizeOf(Lens), 0);
  States.Data[0] := Ord(eItsMe);
  Lens.Data[0] := 2;
  Model.classTable := @Classes.Data;
  Model.stateTable := @States.Data;
  Model.charLenTable := @Lens.Data;
  Model.classFactor := 1;
  Model.CharsetID := UTF8_CHARSET;
  Machine := TnsCodingStateMachine.Create(Model);
  try
    Assert.AreEqual<Integer>(Ord(eItsMe), Ord(Machine.NextState(AnsiChar($FF))));
    Assert.AreEqual<Integer>(2, Integer(Machine.GetCurrentCharLen));
  finally
    Machine.Free;
  end;
end;

procedure TChsTableTests.PackedNibblesIncludeHighBitAndWordBoundary;
var
  Words: packed record Header: UInt64; Data: array [0..1] of Cardinal; end;
  Pkg: nsPkgInt;
  I: Integer;
begin
  Words.Header := 0;
  Words.Data[0] := $76543210;
  Words.Data[1] := $FEDCBA98;
  Pkg.idxsft := eIdxSft4bits;
  Pkg.sftmsk := eSftMsk4bits;
  Pkg.bitsft := eBitSft4bits;
  Pkg.unitmsk := eUnitMsk4bits;
  Pkg.data := @Words.Data[0];
  for I := 0 to 15 do
    Assert.AreEqual<Integer>(I, GETFROMPCK(I, @Pkg));
end;

function TDistributionProbe.GetOrder(Str: PAnsiChar): PRInt32;
begin
  Result := FOrder;
end;

procedure TDistributionProbe.Configure(Table: pPRInt16; Count: Integer);
begin
  mCharToFreqOrder := Table;
  mTableSize := Count;
  mTypicalDistributionRatio := 1;
  Reset;
end;

procedure TDistributionProbe.FeedOrder(Value: Integer);
begin
  FOrder := Value;
  HandleOneChar(nil, 2); // GetOrder is overridden and does not dereference Str.
end;

function TDistributionProbe.Frequent: Cardinal;
begin
  Result := mFreqChars;
end;

function TDistributionProbe.Total: Cardinal;
begin
  Result := mTotalChars;
end;

procedure TChsTableTests.DistributionChecksActualLengthBeforeReading;
var
  Table: packed record Header: UInt64; Data: array [0..1] of SmallInt;
    Canary: SmallInt; end;
  Probe: TDistributionProbe;
begin
  Table.Header := 0;
  Table.Data[0] := 511;
  Table.Data[1] := 512;
  Table.Canary := 0; // Would increment Frequent if the order=Count guard broke.
  Probe := TDistributionProbe.Create;
  try
    Probe.Configure(@Table.Data[0], 2);
    Probe.FeedOrder(-1);
    Probe.FeedOrder(0);
    Probe.FeedOrder(1);
    Probe.FeedOrder(2);
    Assert.AreEqual<Cardinal>(3, Probe.Total);
    Assert.AreEqual<Cardinal>(1, Probe.Frequent);
    Probe.Reset;
    Assert.AreEqual<Cardinal>(0, Probe.Total);
    Assert.AreEqual<Cardinal>(0, Probe.Frequent);
  finally
    Probe.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TChsTableTests);
end.
