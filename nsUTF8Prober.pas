unit nsUTF8Prober;

interface

uses
  nsCore,
  CustomDetector;

type
  TnsUTF8Prober = class(TCustomDetector)
  private
    mNumOfMBChar: Integer;
    mRemaining: Integer;
    mMinTrail, mMaxTrail: Byte;
  public
    constructor Create; override;
    function GetDetectedCharset: eInternalCharsetID; override;
    function HandleData(aBuf: PAnsiChar; aLen: integer): eProbingState; override;
    procedure Reset; override;
    function GetConfidence: float; override;
  end;

implementation

const
  ONE_CHAR_PROB: float = 0.50;

constructor TnsUTF8Prober.Create;
begin
  inherited Create;
  Reset;
end;

function TnsUTF8Prober.GetDetectedCharset: eInternalCharsetID;
begin
  Result := UTF8_CHARSET;
end;

function TnsUTF8Prober.HandleData(aBuf: PAnsiChar; aLen: integer): eProbingState;
var
  i: Integer;
  B: Byte;
begin
  Result := inherited HandleData(aBuf, aLen);
  if Result = psNotMe then
    Exit;

  for i := 0 to Pred(aLen) do
  begin
    B := Byte(aBuf[i]);
    if mRemaining > 0 then
    begin
      if (B < mMinTrail) or (B > mMaxTrail) then
      begin
        mState := psNotMe;
        Break;
      end;
      Dec(mRemaining);
      mMinTrail := $80;
      mMaxTrail := $BF;
    end
    else if B >= $80 then
    begin
      mMinTrail := $80;
      mMaxTrail := $BF;
      case B of
        $C2..$DF: mRemaining := 1;
        $E0..$EF: mRemaining := 2;
        $F0..$F4: mRemaining := 3;
      else
        mState := psNotMe;
        Break;
      end;
      case B of
        $E0: mMinTrail := $A0;
        $ED: mMaxTrail := $9F;
        $F0: mMinTrail := $90;
        $F4: mMaxTrail := $8F;
      end;
    end;
    if (mRemaining = 0) and (B >= $80) then
      Inc(mNumOfMBChar);
  end;

  Result := mState;
end;

procedure TnsUTF8Prober.Reset;
begin
  if mEnabled then
    mState := psDetecting
  else
    mState := psNotMe;
  mNumOfMBChar := 0;
  mRemaining := 0;
end;

function TnsUTF8Prober.GetConfidence: float;
var
  Unlike: float;
  i: Integer;
begin
  if mRemaining <> 0 then
    Exit(SURE_NO);
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
