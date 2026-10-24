// +----------------------------------------------------------------------+
// |    chsdet - Charset Detector Library                                 |
// +----------------------------------------------------------------------+
// | Copyright (C) 2006, Nick Yakowlew     http://chsdet.sourceforge.net  |
// +----------------------------------------------------------------------+
// | Based on Mozilla sources     http://www.mozilla.org/projects/intl/   |
// +----------------------------------------------------------------------+
// | This library is free software; you can redistribute it and/or modify |
// | it under the terms of the GNU General Public License as published by |
// | the Free Software Foundation; either version 2 of the License, or    |
// | (at your option) any later version.                                  |
// | This library is distributed in the hope that it will be useful       |
// | but WITHOUT ANY WARRANTY; without even the implied warranty of       |
// | MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                 |
// | See the GNU Lesser General Public License for more details.          |
// | http://www.opensource.org/licenses/lgpl-license.php                  |
// +----------------------------------------------------------------------+
//
// $Id: nsSBCSGroupProber.pas,v 1.3 2007/05/26 13:09:38 ya_nick Exp $

unit nsSBCSGroupProber;

interface
uses
	nsCore,
  nsGroupProber;

type
	TnsSBCSGroupProber = class(TnsGroupProber)
    private
      mInInternationalWord: Boolean;
      mAsciiPrefix: RawByteString;
      mAsciiPrefixLength: Integer;
      procedure AppendAsciiPrefix(Data: PAnsiChar; Count: Integer);
		public
      constructor Create; reintroduce;
      procedure Reset; override;
      function HandleData(aBuf: PAnsiChar;  aLen: integer): eProbingState; override;
//      {$ifdef DEBUG_chardet}
//      procedure DumpStatus; override;
//      {$endif}
  end;

implementation
uses
	System.SysUtils,
	nsHebrewProber,
  nsSBCharSetProber,
  LangCyrillicModel,
  LangGreekModel,
  LangBulgarianModel,
  LangHebrewModel;

{ TnsSBCSGroupProber }
const
	NUM_OF_PROBERS = 13;

constructor TnsSBCSGroupProber.Create;
var
  hebprober: TnsHebrewProber;
  i: integer;
begin
  mNumOfProbers := NUM_OF_PROBERS;
  SetLength(mProbers, NUM_OF_PROBERS);
  SetLength(mIsActive, NUM_OF_PROBERS);
  SetLength(mProberStates, NUM_OF_PROBERS);
  mProbers[0] := TnsSingleByteCharSetProber.Create(Win1251Model);
  mProbers[1] := TnsSingleByteCharSetProber.Create(Koi8rModel);
  mProbers[2] := TnsSingleByteCharSetProber.Create(Latin5Model);
  mProbers[3] := TnsSingleByteCharSetProber.Create(MacCyrillicModel);
  mProbers[4] := TnsSingleByteCharSetProber.Create(Ibm866Model);
  mProbers[5] := TnsSingleByteCharSetProber.Create(Ibm855Model);
  mProbers[6] := TnsSingleByteCharSetProber.Create(Latin7Model);
  mProbers[7] := TnsSingleByteCharSetProber.Create(Win1253Model);
  mProbers[8] := TnsSingleByteCharSetProber.Create(Latin5BulgarianModel);
  mProbers[9] := TnsSingleByteCharSetProber.Create(Win1251BulgarianModel);

  hebprober := TnsHebrewProber.Create;
  // Notice: Any change in these indexes - 10,11,12 must be reflected
  // in the code below as well.
  mProbers[10]:= hebprober;
  mProbers[11]:= TnsSingleByteCharSetProber.Create(Win1255Model,FALSE,hebprober);(* Logical Hebrew*)
  mProbers[12]:= TnsSingleByteCharSetProber.Create(Win1255Model,TRUE,hebprober); (* Visual Hebrew*)
  (* Tell the Hebrew prober about the logical and visual probers*)
  if (mProbers[10]<>nil)and(mProbers[11]<>nil)and(mProbers[12]<>nil) then
    (* all are not null*)
    hebprober.SetModelProbers(mProbers[11],mProbers[12])
  else
    (* One or more is null. avoid any Hebrew probing, null them all*)
    for i := 10 to 12 do
      begin
        mProbers[i].Free;
        mProbers[i] := nil;
      end;

  inherited Create;
  (* disable latin2 before latin1 is available, otherwise all latin1 *)
  (* will be detected as latin2 because of their similarity.*)
  // mProbers[10] = new nsSingleByteCharSetProber(&Latin2HungarianModel);
  // mProbers[11] = new nsSingleByteCharSetProber(&Win1250HungarianModel);
end;

procedure TnsSBCSGroupProber.Reset;
begin
  inherited Reset;
  mInInternationalWord := False;
  mAsciiPrefix := '';
  mAsciiPrefixLength := 0;
end;

procedure TnsSBCSGroupProber.AppendAsciiPrefix(Data: PAnsiChar; Count: Integer);
var
  Required, Capacity: Integer;
begin
  if Count <= 0 then
    Exit;
  if Count > MaxInt - 1 - mAsciiPrefixLength then
    raise EOutOfMemory.Create('SBCS ASCII prefix is too long');
  Required := mAsciiPrefixLength + Count;
  Capacity := Length(mAsciiPrefix);
  if Capacity < Required then
  begin
    // Geometric growth keeps one-byte feeds linear in the prefix length.
    if Capacity < 64 then
      Capacity := 64;
    while Capacity < Required do
      if Capacity > (MaxInt - 1) div 2 then
        Capacity := Required
      else
        Capacity := Capacity * 2;
    SetLength(mAsciiPrefix, Capacity);
  end;
  Move(Data^, mAsciiPrefix[mAsciiPrefixLength + 1], Count);
  mAsciiPrefixLength := Required;
end;

function TnsSBCSGroupProber.HandleData(aBuf: PAnsiChar; aLen: integer): eProbingState;
var
  Segment: PAnsiChar;
  Current: PAnsiChar;
  Limit: PAnsiChar;
  Count: Integer;
begin
  Result := mState;
  if aLen <= 0 then
    Exit;

  Current := aBuf;
  Limit := aBuf + aLen;
  while Current < Limit do
  begin
    Segment := Current;
    while (Current < Limit) and
      ((Byte(Current^) >= $80) or (Current^ in ['A'..'Z', 'a'..'z'])) do
    begin
      if Byte(Current^) >= $80 then
        mInInternationalWord := True;
      Inc(Current);
    end;
    Count := Current - Segment;
    if mInInternationalWord then
    begin
      // Replay an earlier ASCII-only block only after this word qualifies.
      // Confidence queries and chunk boundaries must not commit or discard it.
      if mAsciiPrefixLength > 0 then
      begin
        inherited HandleData(PAnsiChar(mAsciiPrefix), mAsciiPrefixLength);
        mAsciiPrefixLength := 0;
      end;
      if Count > 0 then
        inherited HandleData(Segment, Count);
    end
    else if Current = Limit then
      AppendAsciiPrefix(Segment, Count);

    if Current < Limit then
    begin
      if mInInternationalWord then
        inherited HandleData(' ', 1);
      mInInternationalWord := False;
      mAsciiPrefixLength := 0;
      Inc(Current);
    end;
  end;
  Result := mState;
end;

{$ifdef DEBUG_chardet}
procedure TnsSBCSGroupProber.DumpStatus;
var
  i: integer;
  cf: float;
  i: integer;
begin
  cf := GetConfidence;
  printf(' SBCS Group Prober --------begin status r'#13#10'');
  for i := 0 to Pred(NUM_OF_SBCS_PROBERS) do
    begin
      if 0 = mIsActive[i] then
	      printf('  inactive: [%s] (i.e. confidence is too low).r'#13#10'',mProbers[i].GetCharSetName)
      else
  	    mProbers[i].DumpStatus;
    end;
  printf(' SBCS Group found best match [%s] confidence %f.r'#13#10'',mProbers[mBestGuess].GetCharSetName,cf);
end;
{$endif}

end.
