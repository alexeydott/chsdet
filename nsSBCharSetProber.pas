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
// $Id: nsSBCharSetProber.pas,v 1.3 2007/05/26 13:09:38 ya_nick Exp $

unit nsSBCharSetProber;

interface

uses
  {$I dbg.inc}
	nsCore,
	CustomDetector;


const
  NUMBER_OF_SEQ_CAT = 4;

type
  TSequenceCounters = array [0..Pred(NUMBER_OF_SEQ_CAT)] of UInt64;

  // Model-specific statistics; zero-initialize before accumulating a new run.
  TSequenceSummary = record
    TotalChar, FreqChar, TotalSeqs: UInt64;
    SeqCounters: TSequenceCounters;
    FirstOrder, LastOrder: Byte;
    HasData: Boolean;
  end;

  SequenceModel = record
    charToOrderMap: PAnsiChar; (* [256] table use to find a char's order*)
    precedenceMatrix: PAnsiChar; (* [SAMPLE_SIZE][SAMPLE_SIZE]; table to find a 2-char sequence's frequency*)
    mTypicalPositiveRatio: float; (* = freqSeqs / totalSeqs *)
    keepEnglishLetter: Boolean; (* says if this script contains English characters (not implemented)*)
    CharsetID: eInternalCharsetID;
  end;

	TnsSingleByteCharSetProber = class(TCustomDetector)
		protected
      mModel: SequenceModel;
      mReversed: Boolean; (* TRUE if we need to reverse every pair in the model lookup*)
      mLastOrder: byte;   (*char order of last character*)
      mTotalSeqs: UInt64;
      mSeqCounters: TSequenceCounters;
      mTotalChar: UInt64; (*characters that fall in our sampling range*)
      mFreqChar: UInt64; (* Optional auxiliary prober for name decision. created and destroyed by the GroupProber*)
      mNameProber: TCustomDetector;

		public
    	constructor Create(model: SequenceModel; reversed: Boolean = FALSE; nameProber: TCustomDetector = nil); reintroduce;
      destructor Destroy; override;
		  function GetDetectedCharset: eInternalCharsetID; override;
		  function HandleData(aBuf: PAnsiChar;  aLen: integer): eProbingState; override;
		  procedure Reset; override;

		  function GetConfidence: float; override;
      procedure AccumulateSummary(var Summary: TSequenceSummary;
        Data: PAnsiChar; Count: Integer);
      procedure ApplySummary(const Summary: TSequenceSummary);
      (* This feature is not implemented yet. any current language model*)
      (* contain this parameter as PR_FALSE. No one is looking at this*)
      (* parameter or calling this method.*)
      (* Moreover, the nsSBCSGroupProber which calls the HandleData of this*)
      (* prober has a hard-coded call to FilterWithoutEnglishLetters which gets rid*)
      (* of the English letters.*)

		  function KeepEnglishLetters: Boolean; virtual;
		  (* (not implemented)*)
   end;

implementation

{$ifdef DEBUG_chardet}
uses
  System.TypInfo,
  System.SysUtils;
{$endif}

const
  SAMPLE_SIZE: byte = 64;
  SYMBOL_CAT_ORDER: byte = 250;
  POSITIVE_CAT = (NUMBER_OF_SEQ_CAT-1);
(*#define NEGATIVE_APPROACH 1*)
{$ifdef NEGATIVE_APPROACH}
  NEGATIVE_CAT = 0;
{$endif}

{ TnsSingleByteCharSetProber }

constructor TnsSingleByteCharSetProber.Create(model: SequenceModel;  reversed: Boolean = FALSE; nameProber: TCustomDetector = nil);
begin
	inherited Create;
  mModel := model;
  mReversed := reversed;
  mNameProber := nameProber;
  Reset;
end;

destructor TnsSingleByteCharSetProber.Destroy;
begin

  inherited;
end;

function TnsSingleByteCharSetProber.GetDetectedCharset: eInternalCharsetID;
begin
  if mNameProber = nil then
    begin
      Result := mModel.CharsetID;
      exit;
    end;
  Result := mNameProber.GetDetectedCharset;
end;

(*#define NEGATIVE_APPROACH 1*)
function TnsSingleByteCharSetProber.GetConfidence: float;
var
	r: float;
begin
{$ifdef NEGATIVE_APPROACH}
  if mTotalSeqs > 0 then
	  if mTotalSeqs > mSeqCounters[NEGATIVE_CAT] * 10 then
      begin
        Result := (mTotalSeqs-mSeqCounters[NEGATIVE_CAT] * 10) / mTotalSeqs * mFreqChar / mTotalChar;
        exit;
      end;
  Result := SURE_NO;
{$else}
(*POSITIVE_APPROACH*)
  if mTotalSeqs > 0 then
    begin
      r := (1.0) * mSeqCounters[POSITIVE_CAT] / mTotalSeqs / mModel.mTypicalPositiveRatio;
      r := r * mFreqChar / mTotalChar;
      if r > SURE_YES then
	      r := SURE_YES;

      Result := r;
      exit;
    end;

  Result := SURE_NO;
{$endif}
end;

procedure CountSequenceOrder(const Model: SequenceModel; Reversed: Boolean;
  Order: Byte; var LastOrder: Byte; var TotalChar, FreqChar, TotalSeqs: UInt64;
  var Counters: TSequenceCounters);
var
  Category: Byte;
begin
  if Order < SYMBOL_CAT_ORDER then
    Inc(TotalChar);
  if Order < SAMPLE_SIZE then
  begin
    Inc(FreqChar);
    if LastOrder < SAMPLE_SIZE then
    begin
      Inc(TotalSeqs);
      if Reversed then
        Category := Byte(Model.precedenceMatrix[Order * SAMPLE_SIZE + LastOrder])
      else
        Category := Byte(Model.precedenceMatrix[LastOrder * SAMPLE_SIZE + Order]);
      Inc(Counters[Category]);
    end;
  end;
  LastOrder := Order;
end;

procedure TnsSingleByteCharSetProber.AccumulateSummary(var Summary: TSequenceSummary;
  Data: PAnsiChar; Count: Integer);
var
  I: Integer;
  Order: Byte;
begin
  if Count <= 0 then
    Exit;
  for I := 0 to Count - 1 do
  begin
    Order := Byte(mModel.charToOrderMap[Byte(Data[I])]);
    if not Summary.HasData then
    begin
      Summary.FirstOrder := Order;
      Summary.LastOrder := 255;
      Summary.HasData := True;
    end;
    CountSequenceOrder(mModel, mReversed, Order, Summary.LastOrder,
      Summary.TotalChar, Summary.FreqChar, Summary.TotalSeqs, Summary.SeqCounters);
  end;
end;

procedure TnsSingleByteCharSetProber.ApplySummary(const Summary: TSequenceSummary);
var
  I: Integer;
  Category: Byte;
begin
  if not Summary.HasData or not mEnabled or (mState = psNotMe) then
    Exit;
  // Internal pairs are already counted; add the single pair at the join.
  if (mLastOrder < SAMPLE_SIZE) and (Summary.FirstOrder < SAMPLE_SIZE) then
  begin
    if mReversed then
      Category := Byte(mModel.precedenceMatrix[Summary.FirstOrder * SAMPLE_SIZE + mLastOrder])
    else
      Category := Byte(mModel.precedenceMatrix[mLastOrder * SAMPLE_SIZE + Summary.FirstOrder]);
    Inc(mTotalSeqs);
    Inc(mSeqCounters[Category]);
  end;
  Inc(mTotalChar, Summary.TotalChar);
  Inc(mFreqChar, Summary.FreqChar);
  Inc(mTotalSeqs, Summary.TotalSeqs);
  for I := Low(mSeqCounters) to High(mSeqCounters) do
    Inc(mSeqCounters[I], Summary.SeqCounters[I]);
  mLastOrder := Summary.LastOrder;
end;

function TnsSingleByteCharSetProber.HandleData(aBuf: PAnsiChar; aLen: integer): eProbingState;
var
  order: byte;
  i: integer;
begin
  Result := inherited HandleData(aBuf, aLen);
  if Result = psNotMe then
    exit;
// TODO - move here call to FilterWithoutEnglishLetters from nsSBCSGroupProber.pas
// if not mModel.keepEnglishLetter then ...

  for i := 0 to Pred(aLen) do
    begin
      order := byte(mModel.charToOrderMap[byte(aBuf[i])]);
      CountSequenceOrder(mModel, mReversed, order, mLastOrder,
        mTotalChar, mFreqChar, mTotalSeqs, mSeqCounters);
    end;
  // Statistical confidence is evidence, not a terminal encoding signature.
  // Keep counting all blocks so an early prefix cannot freeze the group on
  // a different candidate merely because callers chose a smaller chunk size.

  Result := mState;
end;

function TnsSingleByteCharSetProber.KeepEnglishLetters: Boolean;
begin
  Result := mModel.keepEnglishLetter;
end;

procedure TnsSingleByteCharSetProber.Reset;
var
	i: integer;
begin
  if mEnabled then
    mState := psDetecting
  else
    mState := psNotMe;
  mLastOrder := 255;
  for i := 0 to Pred(NUMBER_OF_SEQ_CAT) do
	  mSeqCounters[i] := 0;
  mTotalSeqs := 0;
  mTotalChar := 0;
  mFreqChar := 0;
end;

end.

