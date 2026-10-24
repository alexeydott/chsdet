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
// $Id: nsMBCSMultiProber.pas,v 1.2 2007/05/26 13:09:38 ya_nick Exp $

unit nsMBCSMultiProber;

interface

uses
  {$I dbg.inc}
	nsCore,
  MultiModelProber,
  JpCntx,
	CharDistribution;

type
  TAnsiCharPair = array [0..1] of AnsiChar;

	TnsMBCSMultiProber = class (TMultiModelProber)
    private
      mDistributionAnalysis: array of TCharDistributionAnalysis;
      mContextAnalysis: array of TJapaneseContextAnalysis;
      mLastChar: array of TAnsiCharPair;
      mBestGuess: integer;
      mStructuralWinner: integer;
      function GetConfidenceFor(index: integer): double; reintroduce;
		public
			constructor Create; reintroduce;
      destructor Destroy; override;
		  function HandleData(aBuf: PAnsiChar; aLen: integer): eProbingState; override;
      function GetConfidence: double; override;
      procedure Reset; override;
      {$ifdef DEBUG_chardet}
      procedure DumpStatus(Dump: string); override;
      {$endif}
end;

implementation
uses
	System.SysUtils,
  nsCodingStateMachine
  {$ifdef DEBUG_chardet}
  ,System.TypInfo
  {$endif}
  ;

{$I 'SJISLangModel.inc'}
{$I 'EUCJPLangModel.inc'}
{$I 'GB18030LangModel.inc'}
{$I 'EUCKRLangModel.inc'}
{$I 'Big5LangModel.inc'}
{$I 'EUCTWLangModel.inc'}



{ TnsMBCSMultiProber }
const
	NUM_OF_PROBERS = 6;


constructor TnsMBCSMultiProber.Create;
begin
  inherited Create;
  SetLength(mDistributionAnalysis, NUM_OF_PROBERS);
  SetLength(mContextAnalysis, NUM_OF_PROBERS);
  SetLength(mLastChar, NUM_OF_PROBERS);

  AddCharsetModel(SJISLangModel);
  mDistributionAnalysis[0] := TSJISDistributionAnalysis.Create;
  mContextAnalysis[0] := TSJISContextAnalysis.Create;

  AddCharsetModel(EUCJPLangModel);
  mDistributionAnalysis[1] := TEUCJPDistributionAnalysis.Create;
  mContextAnalysis[1] := nil;

  AddCharsetModel(GB18030LangModel);
  mDistributionAnalysis[2] := TGB2312DistributionAnalysis.Create;
  mContextAnalysis[2] := nil;

  AddCharsetModel(EUCKRLangModel);
  mDistributionAnalysis[3] := TEUCKRDistributionAnalysis.Create;
  mContextAnalysis[3] := nil;

  AddCharsetModel(Big5LangModel);
  mDistributionAnalysis[4] := TBig5DistributionAnalysis.Create;
  mContextAnalysis[4] := nil;

  AddCharsetModel(EUCTWLangModel);
  mDistributionAnalysis[5] := TEUCTWDistributionAnalysis.Create;
  mContextAnalysis[5] := nil;

end;

destructor TnsMBCSMultiProber.Destroy;
var
  i: integer;
begin
  inherited;
  for i := 0 to Pred(mCharsetsCount) do
    begin
      if mDistributionAnalysis[i] <> nil then
        mDistributionAnalysis[i].Free;
      if mContextAnalysis[i] <> nil then
        mContextAnalysis[i].Free;
    end;

  SetLength(mDistributionAnalysis, 0);
  SetLength(mContextAnalysis, 0);

end;

{$ifdef DEBUG_chardet}
procedure TnsMBCSMultiProber.DumpStatus(Dump: string);
var
  i: integer;
begin
  AddDump(Dump + ' Current state ' + GetEnumName(TypeInfo(eProbingState), integer(mState)));
  AddDump(Format('%30s - %10s - %5s',
          ['Prober',
           'State',
           'Conf']));
  for i := 0 to Pred(mCharsetsCount) do
    AddDump(Format('%30s - %10s - %1.5f',
          [GetEnumName(TypeInfo(eInternalCharsetID), integer(mCodingSM[i].GetCharsetID)),
           GetEnumName(TypeInfo(eProbingState), integer(mSMState[i])),
           GetConfidenceFor(i)
           ]));
end;
{$endif}

function TnsMBCSMultiProber.HandleData(aBuf: PAnsiChar; aLen: integer): eProbingState;
var
  i: integer;
  j: integer;
  charLen: PRUint32;
  codingState: nsSMState;
begin
  if aLen <= 0 then
  begin
    Result := mState;
    Exit;
  end;

  // State machines must see the original stream. Removing ASCII can join
  // unrelated bytes into a valid-looking multibyte character.
    {$IFDEF DEBUG_chardet}
     AddDump('MultiByte - HandleData - start');
    {$endif}

    for i := 0 to Pred(aLen) do
      begin
        for j := mCharsetsCount - 1 downto 0 do
        begin
          if (not mCodingSM[j].Enabled) or
             (mSMState[j] = psNotMe) then
            continue;

          codingState := mCodingSM[j].NextState(aBuf[i]);
          if codingState = eError then
            begin
              mSMState[j] := psNotMe;
              if (mStructuralWinner = j) or
                 (mDetectedCharset = mCodingSM[j].GetCharsetID) then
              begin
                if mStructuralWinner = j then
                  mStructuralWinner := -1;
                mState := psDetecting;
                mDetectedCharset := UNKNOWN_CHARSET;
              end;
              Dec(mActiveSM);
              if mActiveSM = 0 then
                begin
                  mState := psNotMe;
                  Result := mState;
                  Exit;
                end;
              continue;
            end;

          if codingState = eItsMe then
            begin
              mStructuralWinner := j;
              mSMState[j] := psFoundIt;
              mState := psFoundIt;
              mDetectedCharset := mCodingSM[j].GetCharsetID;
              // A complete GB18030 character identifies the family, not the
              // validity of its remaining input. Leave the absorbing eItsMe
              // state and validate the next character, even in this block.
              mCodingSM[j].Reset;
              Continue;
            end;

          if codingState = eStart then
            begin
              charLen := mCodingSM[j].GetCurrentCharLen;
              if mDistributionAnalysis[j] <> nil then
                begin
                  if i = 0 then
                    begin
                      mLastChar[j][1] := aBuf[0];
                      if mContextAnalysis[j] <> nil then
                        mContextAnalysis[j].HandleOneChar(@mLastChar[j][0], charLen);
                      mDistributionAnalysis[j].HandleOneChar(@mLastChar[j][0], charLen);
                    end
                  else
                    begin
                      if mContextAnalysis[j] <> nil then
                        mContextAnalysis[j].HandleOneChar(aBuf + i - 1, charLen);
                      mDistributionAnalysis[j].HandleOneChar(aBuf + i - 1, charLen);
                    end;
                end;

              if (mContextAnalysis[j] <> nil) and
                 mContextAnalysis[j].GotEnoughData and
    	           (GetConfidenceFor(j) > SHORTCUT_THRESHOLD) then
                begin
                  mSMState[j] := psFoundIt;
    		          mState := psFoundIt;
                  mDetectedCharset := mCodingSM[j].GetCharsetID;
                  // Statistical evidence is provisional: validate the rest of
                  // this block as well as subsequent blocks before accepting it.
                end;
            end;
        end;
      end;

    for i := 0 to Pred(mCharsetsCount) do
      mLastChar[i][0] := aBuf[aLen - 1];

    if mActiveSM = 1 then
      begin
        for i := 0 to Pred(mCharsetsCount) do
          if mSMState[i] <> psNotMe then
            begin
              if GetConfidenceFor(i) > SURE_NO then
                begin
                  mSMState[i] := psFoundIt;
                  mState := psFoundIt;
                  mDetectedCharset := mCodingSM[i].GetCharsetID;
                end;
              break;
            end;
      end;

    {$IFDEF DEBUG_chardet}
     AddDump('MultiByte - HandleData - end');
    {$endif}

  Result := mState;
end;

function TnsMBCSMultiProber.GetConfidenceFor(index: integer): double;
var
  contxtCf: double;
  distribCf: double;
begin
  if not mCodingSM[index].IsAtCharacterBoundary then
    Exit(SURE_NO);
  if mContextAnalysis[index] <> nil then
    contxtCf := mContextAnalysis[index].GetConfidence
  else
    contxtCf := -1;

  distribCf := mDistributionAnalysis[index].GetConfidence;

  if contxtCf > distribCf then
    Result := contxtCf
  else
    Result := distribCf;
end;

function TnsMBCSMultiProber.GetConfidence: double;
var
  i: integer;
  conf,
  bestConf: double;
begin
  // A confidence query must preserve a completed structural detection.
  if (mStructuralWinner >= 0) and
     (mSMState[mStructuralWinner] <> psNotMe) and
     mCodingSM[mStructuralWinner].IsAtCharacterBoundary then
  begin
    mDetectedCharset := mCodingSM[mStructuralWinner].GetCharsetID;
    Exit(SURE_YES);
  end;
  if mState = psNotMe then
  begin
    mDetectedCharset := UNKNOWN_CHARSET;
    Exit(SURE_NO);
  end;

  mBestGuess := -1;
  bestConf := SURE_NO;
  for i := 0 to Pred(mCharsetsCount) do
    begin
      if mSMState[i] = psNotMe then
        continue;
      if mDistributionAnalysis[i] = nil then
        continue;
      conf := GetConfidenceFor(i);
      if conf > bestConf then
        begin
          mBestGuess := i;
          bestConf := conf;
        end;
    end;
  Result := bestConf;
  if mBestGuess > -1 then
    mDetectedCharset := mCodingSM[mBestGuess].GetCharsetID
  else
    mDetectedCharset := UNKNOWN_CHARSET;
end;

procedure TnsMBCSMultiProber.Reset;
var
  i: integer;
begin
  inherited Reset;
  mStructuralWinner := -1;
  mBestGuess := -1;
  for i := 0 to Pred(mCharsetsCount) do
    begin
      if mDistributionAnalysis[i] <> nil then
        mDistributionAnalysis[i].Reset;
      if mContextAnalysis[i] <> nil then
        mContextAnalysis[i].Reset;
      FillChar(mLastChar[i], SizeOf(mLastChar[i]), 0);
    end;
end;

end.
