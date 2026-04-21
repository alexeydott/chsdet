unit nsUTF8Prober;

interface

uses
  nsCore,
  CustomDetector,
  nsCodingStateMachine;

type
  TnsUTF8Prober = class(TCustomDetector)
  private
    mCodingSM: TnsCodingStateMachine;
    mNumOfMBChar: Integer;
  public
    constructor Create; override;
    destructor Destroy; override;
    function GetDetectedCharset: eInternalCharsetID; override;
    function HandleData(aBuf: PAnsiChar; aLen: integer): eProbingState; override;
    procedure Reset; override;
    function GetConfidence: float; override;
  end;

implementation

{$I 'UTF8LangModel.inc'}

const
  ONE_CHAR_PROB: float = 0.50;

constructor TnsUTF8Prober.Create;
begin
  inherited Create;
  mCodingSM := TnsCodingStateMachine.Create(UTF8LangModel);
  Reset;
end;

destructor TnsUTF8Prober.Destroy;
begin
  mCodingSM.Free;
  inherited;
end;

function TnsUTF8Prober.GetDetectedCharset: eInternalCharsetID;
begin
  Result := UTF8_CHARSET;
end;

function TnsUTF8Prober.HandleData(aBuf: PAnsiChar; aLen: integer): eProbingState;
var
  i: Integer;
  CodingState: nsSMState;
begin
  Result := inherited HandleData(aBuf, aLen);
  if Result = psNotMe then
    Exit;

  for i := 0 to Pred(aLen) do
  begin
    CodingState := mCodingSM.NextState(aBuf[i]);
    case CodingState of
      eError:
        begin
          mState := psNotMe;
          Break;
        end;
      eItsMe:
        begin
          mState := psFoundIt;
          Break;
        end;
      eStart:
        if mCodingSM.GetCurrentCharLen >= 2 then
          Inc(mNumOfMBChar);
    end;
  end;

  if (mState = psDetecting) and (GetConfidence > SHORTCUT_THRESHOLD) then
    mState := psFoundIt;

  Result := mState;
end;

procedure TnsUTF8Prober.Reset;
begin
  if mEnabled then
    mState := psDetecting
  else
    mState := psNotMe;
  mCodingSM.Reset;
  mNumOfMBChar := 0;
end;

function TnsUTF8Prober.GetConfidence: float;
var
  Unlike: float;
  i: Integer;
begin
  case mState of
    psFoundIt:
      Exit(SURE_YES);
    psNotMe:
      Exit(SURE_NO);
  end;

  unlike := 0.99;
  if mNumOfMBChar < 6 then
  begin
    for i := 0 to Pred(mNumOfMBChar) do
      unlike := unlike * ONE_CHAR_PROB;
    Result := 1.0 - unlike;
  end
  else
    Result := SURE_YES;
end;

end.
