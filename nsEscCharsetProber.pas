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
// $Id: nsEscCharsetProber.pas,v 1.3 2007/05/26 13:09:38 ya_nick Exp $

unit nsEscCharsetProber;

interface

uses
	nsCore,
	MultiModelProber;

type
	TnsEscCharSetProber = class (TMultiModelProber)
    private
      mIso2022CnTail: array [0..2] of AnsiChar;
      mIso2022CnTailLen: Integer;
      function IsCharsetEnabled(Charset: eInternalCharsetID): Boolean;
      function ContainsIso2022CnDesignator(aBuf: PAnsiChar; aLen: Integer): Boolean;
      procedure UpdateIso2022CnTail(aBuf: PAnsiChar; aLen: Integer);
		public
    	constructor Create; override;
      function HandleData(aBuf: PAnsiChar; aLen: integer): eProbingState; override;
      procedure Reset; override;
      function GetConfidence: float; override;
  end;


implementation
uses
  nsCodingStateMachine,
  CustomDetector;
  
{$I 'ISO2022KRLangModel.inc'}
{$I 'ISO2022JPLangModel.inc'}
{$I 'ISO2022CNLangModel.inc'}
{$I 'HZLangModel.inc'}

{ TnsEscCharSetProber }
const
	NUM_OF_ESC_CHARSETS = 4;

constructor TnsEscCharSetProber.Create;
begin
  inherited;
  AddCharsetModel(HZSMModel);
  AddCharsetModel(ISO2022CNSMModel);
  AddCharsetModel(ISO2022JPSMModel);
  AddCharsetModel(ISO2022KRSMModel);
  Reset;
end;

function TnsEscCharSetProber.IsCharsetEnabled(Charset: eInternalCharsetID): Boolean;
var
  I: Integer;
begin
  for I := 0 to Pred(mCharsetsCount) do
    if mCodingSM[I].GetCharsetID = Charset then
      Exit(mCodingSM[I].Enabled);

  Result := False;
end;

function TnsEscCharSetProber.ContainsIso2022CnDesignator(aBuf: PAnsiChar; aLen: Integer): Boolean;
  function ByteAt(Index: Integer): Byte;
  begin
    if Index < mIso2022CnTailLen then
      Result := Byte(mIso2022CnTail[Index])
    else
      Result := Byte(aBuf[Index - mIso2022CnTailLen]);
  end;
var
  TotalLen: Integer;
  I: Integer;
  B0: Byte;
  B1: Byte;
  B2: Byte;
  B3: Byte;
begin
  Result := False;
  if aLen <= 0 then
    Exit;

  TotalLen := mIso2022CnTailLen + aLen;
  if TotalLen < 4 then
    Exit;

  for I := 0 to TotalLen - 4 do
  begin
    B0 := ByteAt(I);
    if B0 <> $1B then
      Continue;

    B1 := ByteAt(I + 1);
    if B1 <> $24 then
      Continue;

    B2 := ByteAt(I + 2);
    B3 := ByteAt(I + 3);

    case B2 of
      $29:
        if B3 in [$41, $45, $47] then
          Exit(True);
      $2A:
        if B3 = $48 then
          Exit(True);
      $2B:
        if B3 in [$49, $4A, $4B, $4C, $4D] then
          Exit(True);
    end;
  end;
end;

procedure TnsEscCharSetProber.UpdateIso2022CnTail(aBuf: PAnsiChar; aLen: Integer);
var
  Buffer: array [0..2] of AnsiChar;
  CopyFromTail: Integer;
  I: Integer;
begin
  if aLen <= 0 then
    Exit;

  if aLen >= Length(mIso2022CnTail) then
  begin
    for I := 0 to High(mIso2022CnTail) do
      mIso2022CnTail[I] := aBuf[aLen - Length(mIso2022CnTail) + I];
    mIso2022CnTailLen := Length(mIso2022CnTail);
    Exit;
  end;

  CopyFromTail := Length(mIso2022CnTail) - aLen;
  if CopyFromTail > mIso2022CnTailLen then
    CopyFromTail := mIso2022CnTailLen;

  for I := 0 to CopyFromTail - 1 do
    Buffer[I] := mIso2022CnTail[mIso2022CnTailLen - CopyFromTail + I];

  for I := 0 to aLen - 1 do
    Buffer[CopyFromTail + I] := aBuf[I];

  mIso2022CnTailLen := CopyFromTail + aLen;
  Move(Buffer[0], mIso2022CnTail[0], mIso2022CnTailLen * SizeOf(AnsiChar));
end;

function TnsEscCharSetProber.HandleData(aBuf: PAnsiChar; aLen: integer): eProbingState;
begin
  if not Enabled then
  begin
    mState := psNotMe;
    Exit(mState);
  end;

  // The historic ISO-2022-CN state table shipped with chardet never accepts
  // RFC 1922 designators like ESC $ ) A / G. Recognize those explicitly so
  // valid ISO-2022-CN and ISO-2022-CN-EXT streams are not lost.
  if IsCharsetEnabled(ISO_2022_CN_CHARSET) and
     ContainsIso2022CnDesignator(aBuf, aLen) then
  begin
    mDetectedCharset := ISO_2022_CN_CHARSET;
    mState := psFoundIt;
    UpdateIso2022CnTail(aBuf, aLen);
    Exit(mState);
  end;

  Result := inherited HandleData(aBuf, aLen);
  UpdateIso2022CnTail(aBuf, aLen);
end;

procedure TnsEscCharSetProber.Reset;
begin
  inherited Reset;
  mIso2022CnTailLen := 0;
  FillChar(mIso2022CnTail, SizeOf(mIso2022CnTail), 0);
end;

function TnsEscCharSetProber.GetConfidence: float;
begin
  case mState of
    psFoundIt:   Result := SURE_YES;
    psNotMe:     Result := SURE_NO;
    psDetecting: Result := (SURE_YES + SURE_NO) / 2;
    else
      Result := 1.1 * SURE_NO;
  end;
end;

end.


