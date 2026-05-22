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
// $Id: nsUniversalDetector.pas,v 1.5 2008/06/22 09:04:20 ya_nick Exp $

unit nsUniversalDetector;

interface
uses
  {$I dbg.inc}
	nsCore,
  CustomDetector;


const
	NUM_OF_CHARSET_PROBERS = 5;

type nsInputState = (
  ePureAscii = 0,
  eEscAscii  = 1,
  eHighbyte  = 2
	) ;

  TObservedByteStats = record
    TotalByteCount: Integer;
    HighByteCount: Integer;
    OemArtByteCount: Integer;
    Oem850ByteCount: Integer;
    Oem852ByteCount: Integer;
    Oem858ByteCount: Integer;
    Win1250ByteCount: Integer;
    Koi8UByteCount: Integer;

    procedure Reset;
    procedure Feed(Value: Byte);
    function LooksLikeOemArt: Boolean;
    function DetectOemTextSignature: eInternalCharsetID;
    function HasKoi8USignal: Boolean;
    function HasWin1250Signal: Boolean;
  end;

  TDisabledCharsetSet = set of eInternalCharsetID;

	TnsUniversalDetector  = class (TObject)
    protected
      mInputState: nsInputState;
      mDone: Boolean;
      mStart: Boolean;
      mGotData: Boolean;
      mSeenZeroByte: Boolean;
      mSeenC1Byte: Boolean;
      mSeenGreek1253Byte: Boolean;
      mSeenGreekIsoByte: Boolean;
      mObservedBytes: TObservedByteStats;
      mLastChar: AnsiChar;
      mDetectedCharset: eInternalCharsetID;
      mDetectedConfidence: float;
      mDisabledCharsets: TDisabledCharsetSet;
      mCharSetProbers: array [0..Pred(NUM_OF_CHARSET_PROBERS)] of TCustomDetector;
      mEscCharSetProber: TCustomDetector;
      mDetectedBOM: eBOMKind;
      mKnownCharsetsCache: RawByteString;

		  procedure Report(aCharsetID: eInternalCharsetID);
      function ReportWithConfidence(aCharsetID: eInternalCharsetID; Confidence: float): Boolean;
      function CheckBOM(aBuf: PAnsiChar; aLen: integer): integer;
      function GetCharsetID(CodePage: integer): eInternalCharsetID;
      function CharsetFromBOM(BOM: eBOMKind): eInternalCharsetID;
      function NormalizeCharsetByObservedBytes(Charset: eInternalCharsetID): eInternalCharsetID;
      function IsCharsetEnabled(Charset: eInternalCharsetID): Boolean;
      function LooksLikeOemArt: Boolean;
      function DetectOemTextSignature: eInternalCharsetID;
      function DetectLegacyByteSignature: eInternalCharsetID;
      procedure DoEnableCharset(Charset: eInternalCharsetID; SetEnabledTo: Boolean);
		public
    	constructor Create;
      destructor Destroy; override;

		  procedure Reset;
		  function HandleData(aBuf: PAnsiChar; aLen: integer): nsResult;
		  procedure DataEnd;

      function GetDetectedCharsetInfo: nsCore.rCharsetInfo;

      function GetKnownCharset(out KnownCharsets: PAnsiChar): integer;
      procedure GetAbout(out About: rAboutHolder);
      procedure DisableCharset(CodePage: integer);

      property Done: Boolean read mDone;
      property BOMDetected: eBOMKind read mDetectedBOM;
      property Confidence: float read mDetectedConfidence;
end;

implementation
uses
  System.SysUtils,
  MultiModelProber,
  nsGroupProber,
	nsMBCSMultiProber,
	nsSBCSGroupProber,
	nsEscCharsetProber,
  nsLatin1Prober,
  MBUnicodeMultiProber,
  nsUTF8Prober;


const
	MINIMUM_THRESHOLD: float  = 0.20;
  OEM_ART_CONFIDENCE: float = 0.95;
  OEM_TEXT_CONFIDENCE: float = 0.80;
  OEM_ART_MIN_BYTES = 64;
  OEM_ART_MIN_HIGH_RATIO: float = 0.15;
  OEM_ART_MIN_ART_HIGH_RATIO: float = 0.70;
  LEGACY_MIN_BYTES = 128;
  LEGACY_MIN_HIGH_BYTES = 20;
  OEM_LATIN_MAX_HIGH_RATIO: float = 0.65;
  KOI8_U_MIN_SIGNATURE_BYTES = 10;
  WINDOWS_1250_MIN_SIGNATURE_BYTES = 20;

  AboutInfo: rAboutHolder = (
    MajorVersionNr: 0;
    MinorVersionNr: 2;
    BuildVersionNr: 6;
    About: 'Charset Detector Library. Copyright (C) 2006 - 2008, Nick Yakowlew. http://chsdet.sourceforge.net';
  );

{ TObservedByteStats }

procedure TObservedByteStats.Reset;
begin
  TotalByteCount := 0;
  HighByteCount := 0;
  OemArtByteCount := 0;
  Oem850ByteCount := 0;
  Oem852ByteCount := 0;
  Oem858ByteCount := 0;
  Win1250ByteCount := 0;
  Koi8UByteCount := 0;
end;

procedure TObservedByteStats.Feed(Value: Byte);
begin
  Inc(TotalByteCount);

  if Value >= $80 then
    Inc(HighByteCount);

  if Value in [$87, $89, $97, $A2] then
    Inc(Oem850ByteCount);
  if Value in [$86, $88, $8B, $94, $98, $A0, $A1, $A3, $A5, $A7, $A9, $AB,
    $B5, $BE, $D4, $D8] then
    Inc(Oem852ByteCount);
  if Value = $D5 then
    Inc(Oem858ByteCount);
  if Value in [$9A, $9C, $9D, $9E, $9F] then
    Inc(Win1250ByteCount);
  if Value in [$A4, $A6, $A7, $AD] then
    Inc(Koi8UByteCount);

  case Value of
    $B0, $B1, $B2, $B3, $B4,
    $B9, $BA, $BB, $BC, $BF,
    $C0, $C1, $C2, $C3, $C4, $C5,
    $C8, $C9, $CA, $CB, $CC, $CD, $CE,
    $D9, $DA, $DB, $DC, $DD, $DE, $DF, $FE:
      Inc(OemArtByteCount);
  end;
end;

function TObservedByteStats.LooksLikeOemArt: Boolean;
begin
  Result :=
    (TotalByteCount >= OEM_ART_MIN_BYTES) and
    (HighByteCount > 0) and
    (OemArtByteCount >= OEM_ART_MIN_BYTES) and
    (HighByteCount / TotalByteCount >= OEM_ART_MIN_HIGH_RATIO) and
    (OemArtByteCount / HighByteCount >= OEM_ART_MIN_ART_HIGH_RATIO);
end;

function TObservedByteStats.DetectOemTextSignature: eInternalCharsetID;
var
  HighRatio: float;
begin
  Result := UNKNOWN_CHARSET;

  if (TotalByteCount < LEGACY_MIN_BYTES) or
     (HighByteCount < LEGACY_MIN_HIGH_BYTES) then
    Exit;

  HighRatio := HighByteCount / TotalByteCount;

  if HighRatio > OEM_LATIN_MAX_HIGH_RATIO then
    Exit;

  if (Oem858ByteCount >= 4) and (Oem850ByteCount >= 20) then
    Exit(IBM858_CHARSET);

  if Oem852ByteCount >= 20 then
    Exit(IBM852_CHARSET);

  if Oem850ByteCount >= 20 then
    Exit(IBM850_CHARSET);

  if Win1250ByteCount >= WINDOWS_1250_MIN_SIGNATURE_BYTES then
    Exit(WINDOWS_1250_CHARSET);
end;

function TObservedByteStats.HasKoi8USignal: Boolean;
begin
  Result := Koi8UByteCount >= KOI8_U_MIN_SIGNATURE_BYTES;
end;

function TObservedByteStats.HasWin1250Signal: Boolean;
begin
  Result := Win1250ByteCount >= WINDOWS_1250_MIN_SIGNATURE_BYTES;
end;

{ TnsUniversalDetector }

constructor TnsUniversalDetector.Create;
begin
	inherited Create;

  mCharSetProbers[0] := TnsMBCSMultiProber.Create;
  mCharSetProbers[1] := TnsSBCSGroupProber.Create;
  mCharSetProbers[2] := TnsLatin1Prober.Create;
  mCharSetProbers[3] := TnsUTF8Prober.Create;
  mCharSetProbers[4] := TMBUnicodeMultiProber.Create;
  mEscCharSetProber  := TnsEscCharSetProber.Create;
  Reset;
end;

destructor TnsUniversalDetector.Destroy;
var
  i: integer;
begin
	for i := 0 to Pred(NUM_OF_CHARSET_PROBERS) do
    mCharSetProbers[i].Free;

  mEscCharSetProber.Free;

  inherited;
end;

procedure TnsUniversalDetector.DataEnd;
var
	proberConfidence: float;
  maxProberConfidence: float;
  LegacyCharset: eInternalCharsetID;
  DetectedCharset: eInternalCharsetID;
  maxProber: PRInt32;
  i: integer;
begin
  if not mGotData then
    (* we haven't got any data yet, return immediately *)
    (* caller program sometimes call DataEnd before anything has been sent to detector*)
    exit;

  if mDetectedCharset <> UNKNOWN_CHARSET then
    begin
      mDone := TRUE;
      exit;
    end;
  case mInputState of
    eHighbyte:
      begin
        if LooksLikeOemArt then
        begin
          if ReportWithConfidence(IBM437_CHARSET, OEM_ART_CONFIDENCE) then
            Exit;
        end;

        LegacyCharset := DetectLegacyByteSignature;
        if LegacyCharset <> UNKNOWN_CHARSET then
        begin
          if ReportWithConfidence(LegacyCharset, OEM_TEXT_CONFIDENCE) then
            Exit;
        end;

        maxProberConfidence := 0.0;
        maxProber := 0;
        for i := 0 to Pred(NUM_OF_CHARSET_PROBERS) do
          begin
            proberConfidence := mCharSetProbers[i].GetConfidence;
            if proberConfidence > maxProberConfidence then
            begin
              maxProberConfidence := proberConfidence;
              maxProber := i;
            end;
          end;
        (*do not report anything because we are not confident of it, that's in fact a negative answer*)
        if maxProberConfidence > MINIMUM_THRESHOLD then
          begin
            DetectedCharset := mCharSetProbers[maxProber].GetDetectedCharset;
            if (DetectedCharset = KOI8_R_CHARSET) and mObservedBytes.HasKoi8USignal then
              DetectedCharset := KOI8_U_CHARSET
            else if (DetectedCharset = WINDOWS_1252_CHARSET) and mObservedBytes.HasWin1250Signal then
              DetectedCharset := WINDOWS_1250_CHARSET;
	          ReportWithConfidence(DetectedCharset, maxProberConfidence);
          end;
      end;
    eEscAscii:
      begin
        DetectedCharset := mEscCharSetProber.GetDetectedCharset;
        proberConfidence := mEscCharSetProber.GetConfidence;
        ReportWithConfidence(DetectedCharset, proberConfidence);
      end;
    else
      begin
      	mDetectedCharset := PURE_ASCII_CHARSET;
        mDetectedConfidence := SURE_YES;
      end;
  end;{case}
  {$ifdef DEBUG_chardet}
  AddDump('Universal detector - DataEnd');
  {$endif}
end;

function TnsUniversalDetector.HandleData(aBuf: PAnsiChar; aLen: integer): nsResult;
var
  i: integer;
  st: eProbingState;
  DetectedCharset: eInternalCharsetID;
  DetectedConfidence: float;
//  startAt: integer;
//newBuf: pChar;
//BufPtr: pChar;
//b: integer;
//tmpBOM: eBOMKind;
begin
//  startAt := 0;
  if mDone then
    begin
      Result := NS_OK;
      exit;
    end;
  if aLen > 0 then
	  mGotData := TRUE;

  (*If the data starts with BOM, we know it is Unicode*)
  if mStart then
    begin
      mStart := FALSE;
      CheckBOM(aBuf, aLen);
      if ReportWithConfidence(CharsetFromBOM(mDetectedBOM), SURE_YES) then
        begin
          mDone := TRUE;
          Result := NS_OK;
          exit;
        end;
    end; {if mStart}

  for i := 0 to Pred(aLen) do
    begin
      mObservedBytes.Feed(Byte(aBuf[i]));
      if aBuf[i] = #0 then
        mSeenZeroByte := TRUE;
      if (Byte(aBuf[i]) >= $80) and (Byte(aBuf[i]) <= $9F) then
        mSeenC1Byte := TRUE;

      case Byte(aBuf[i]) of
        $A1, $A2:
          mSeenGreek1253Byte := TRUE;
        $B5, $B6:
          mSeenGreekIsoByte := TRUE;
      end;

      (*other than 0xa0, if every othe character is ascii, the page is ascii*)
      if (Byte(aBuf[i]) >= $80) and (aBuf[i] <> #$A0) then
        begin
          (*Since many Ascii only page contains NBSP *)
          (*we got a non-ascii byte (high-byte)*)
          if mInputState <> eHighbyte then
            begin
              (*adjust state*)
              mInputState := eHighbyte;
            end;
        end
      else
        begin
          (*ok, just pure ascii so *)
          if (mInputState = ePureAscii) and
          	 ((aBuf[i] = #$1B) or
             	(aBuf[i] = '{') and
              (mLastChar = '~')) then
            (*found escape character or HZ "~{"*)
            mInputState := eEscAscii;

          mLastChar := aBuf[i];
        end;
    end;

  case mInputState of
    eEscAscii:
      begin
        {$ifdef DEBUG_chardet}
        AddDump('Universal detector - Escape Detector started');
        {$endif}
        st := mEscCharSetProber.HandleData(aBuf,aLen);
        if st = psFoundIt then
          begin
            DetectedCharset := mEscCharSetProber.GetDetectedCharset;
            DetectedConfidence := mEscCharSetProber.GetConfidence;
            if ReportWithConfidence(DetectedCharset, DetectedConfidence) then
              mDone := TRUE;
          end;
      end;
    eHighbyte:
      begin
        {$ifdef DEBUG_chardet}
        AddDump('Universal detector - HighByte Detector started');
        {$endif}
        for i := 0 to Pred(NUM_OF_CHARSET_PROBERS) do
          begin
          if (mCharSetProbers[i] is TMBUnicodeMultiProber) and
             (mDetectedBOM = BOM_Not_Found) and
             (not mSeenZeroByte) then
            continue;
//newBuf := AllocMem(aLen+StartAt);
//BufPtr := newBuf;
//try
//tmpBOM := BOM_Not_Found;
//if mDetectedBOM = BOM_Not_Found then
//begin
////case mCharSetProbers[i].GetDetectedCharset of
//// UTF16_BE_CHARSET: tmpBOM := BOM_UCS4_BE;
//// UTF16_LE_CHARSET: tmpBOM := BOM_UCS4_LE;
//// else
////  tmpBOM := BOM_Not_Found;
////end;
//tmpBOM := BOM_UTF16_BE;
//end;
//for b:=0 to integer(KnownBOM[tmpBOM][0])-1 do
//begin
//BufPtr^ := KnownBOM[tmpBOM][b+1];
//inc(BufPtr);
//end;
//
//for b:=0 to aLen do
//begin
//BufPtr^ := aBuf[b];
//inc(BufPtr);
//end;
          st := mCharSetProbers[i].HandleData(aBuf,aLen);
//          st := mCharSetProbers[i].HandleData(newBuf,aLen+startAt);
          if st = psFoundIt then
            begin
              DetectedCharset := mCharSetProbers[i].GetDetectedCharset;
              DetectedConfidence := mCharSetProbers[i].GetConfidence;
              if ReportWithConfidence(DetectedCharset, DetectedConfidence) then
                mDone:= TRUE;
//              Result := NS_OK;
              break;
            end;
//finally
//FreeMem(newBuf, aLen);
//end;
        end;
      end;
    else
    (*pure ascii*)
    begin
      (*do nothing here*)
    end;
  end;{case}
  Result := NS_OK;
end;

procedure TnsUniversalDetector.Report(aCharsetID: eInternalCharsetID);
begin
  ReportWithConfidence(aCharsetID, mDetectedConfidence);
end;

function TnsUniversalDetector.ReportWithConfidence(aCharsetID: eInternalCharsetID; Confidence: float): Boolean;
var
  NormalizedCharset: eInternalCharsetID;
begin
  Result := False;

	if (aCharsetID = UNKNOWN_CHARSET) or
  	 (mDetectedCharset <> UNKNOWN_CHARSET) then
    Exit;

  NormalizedCharset := NormalizeCharsetByObservedBytes(aCharsetID);
  if not IsCharsetEnabled(NormalizedCharset) then
    Exit;

  mDetectedCharset := NormalizedCharset;
  mDetectedConfidence := Confidence;
  Result := True;
end;

procedure TnsUniversalDetector.Reset;
var
  i: integer;
begin
  mDone := FALSE;
  mStart := TRUE;
  mDetectedCharset := UNKNOWN_CHARSET;
  mDetectedConfidence := 0.0;
  mGotData := FALSE;
  mSeenZeroByte := FALSE;
  mSeenC1Byte := FALSE;
  mSeenGreek1253Byte := FALSE;
  mSeenGreekIsoByte := FALSE;
  mObservedBytes.Reset;
  mInputState := ePureAscii;
  mLastChar := #0; (*illegal value as signal*)
  mEscCharSetProber.Reset;
  for i := 0 to Pred(NUM_OF_CHARSET_PROBERS) do
	  mCharSetProbers[i].Reset;
  mDetectedBOM := BOM_Not_Found;
  mKnownCharsetsCache := '';
end;

function TnsUniversalDetector.GetDetectedCharsetInfo: nsCore.rCharsetInfo;
begin
  Result := KNOWN_CHARSETS[mDetectedCharset];
end;

function TnsUniversalDetector.GetKnownCharset(out KnownCharsets: PAnsiChar): integer;
var
  i: integer;
begin
  mKnownCharsetsCache := '';
  for i := integer(low(KNOWN_CHARSETS)) to integer(High(KNOWN_CHARSETS)) do
    mKnownCharsetsCache := mKnownCharsetsCache + AnsiString(#10) +
      KNOWN_CHARSETS[eInternalCharsetID(i)].Name + AnsiString(' - ') +
      AnsiString(IntToStr(KNOWN_CHARSETS[eInternalCharsetID(i)].CodePage));

  KnownCharsets := PAnsiChar(mKnownCharsetsCache);
  Result := Length(mKnownCharsetsCache);
end;

procedure TnsUniversalDetector.GetAbout(out About: rAboutHolder);
begin
  About := AboutInfo;
end;

function TnsUniversalDetector.CheckBOM(aBuf: PAnsiChar; aLen: integer): integer;
  function BOMLength(BOM: eBOMKind): integer;
  begin
    Result := integer(KnownBOM[BOM, 0]);
  end;
var
  i, b: integer;
  Same: Boolean;
begin
  Result := 0;
  for i := integer(low(KnownBOM))+1 to integer(high(KnownBOM)) do
    if aLen >= BOMLength(eBOMKind(i)) then
      begin
        Same := true;
        for b := 0 to BOMLength(eBOMKind(i)) - 1 do
          if (aBuf[b] <> KnownBOM[eBOMKind(i), b+1]) then
            begin
              Same := false;
              break;
            end;
        if Same then
          begin
            mDetectedBOM := eBOMKind(i);
            Result := BOMLength(mDetectedBOM);
            exit;
          end;
      end;
end;

function TnsUniversalDetector.CharsetFromBOM(BOM: eBOMKind): eInternalCharsetID;
begin
  case BOM of
    BOM_UCS4_BE:
      Result := UTF32_BE_CHARSET;
    BOM_UCS4_LE:
      Result := UTF32_LE_CHARSET;
    BOM_UCS4_2143:
      Result := UCS4_LE_CHARSET;
    BOM_UCS4_3412:
      Result := UCS4_BE_CHARSET;
    BOM_UTF16_BE:
      Result := UTF16_BE_CHARSET;
    BOM_UTF16_LE:
      Result := UTF16_LE_CHARSET;
    BOM_UTF8:
      Result := UTF8_CHARSET;
  else
    Result := UNKNOWN_CHARSET;
  end;
end;

function TnsUniversalDetector.NormalizeCharsetByObservedBytes(Charset: eInternalCharsetID): eInternalCharsetID;
begin
  Result := Charset;

  if (Charset = ISO_8859_7_CHARSET) and
     mSeenGreek1253Byte and
     (not mSeenGreekIsoByte) then
    begin
      Result := WINDOWS_1253_CHARSET;
      Exit;
    end;

  if not mSeenC1Byte then
    Exit;

  case Charset of
    LATIN5_BULGARIAN_CHARSET:
      Result := WINDOWS_BULGARIAN_CHARSET;
    ISO_8859_5_CHARSET:
      Result := WINDOWS_1251_CHARSET;
    ISO_8859_7_CHARSET:
      Result := WINDOWS_1253_CHARSET;
    ISO_8859_8_CHARSET:
      Result := WINDOWS_1255_CHARSET;
  end;
end;

function TnsUniversalDetector.IsCharsetEnabled(Charset: eInternalCharsetID): Boolean;
begin
  Result := not (Charset in mDisabledCharsets);
end;

function TnsUniversalDetector.LooksLikeOemArt: Boolean;
begin
  Result := mObservedBytes.LooksLikeOemArt;
end;

function TnsUniversalDetector.DetectLegacyByteSignature: eInternalCharsetID;
begin
  Result := DetectOemTextSignature;
end;

function TnsUniversalDetector.DetectOemTextSignature: eInternalCharsetID;
begin
  Result := mObservedBytes.DetectOemTextSignature;
end;

procedure TnsUniversalDetector.DisableCharset(CodePage: integer);
var
  i: Integer;
begin
  for i := Integer(Low(KNOWN_CHARSETS)) + 1 to Integer(High(KNOWN_CHARSETS)) do
    if KNOWN_CHARSETS[eInternalCharsetID(i)].CodePage = CodePage then
      begin
        Include(mDisabledCharsets, eInternalCharsetID(i));
        DoEnableCharset(eInternalCharsetID(i), False);
      end;
end;

function TnsUniversalDetector.GetCharsetID(CodePage: integer): eInternalCharsetID;
var
  i: integer;
begin
  for i := integer(low(KNOWN_CHARSETS))+1 to integer(high(KNOWN_CHARSETS)) do
    if (KNOWN_CHARSETS[eInternalCharsetID(i)].CodePage = CodePage) then
      begin
        Result := eInternalCharsetID(i);
        exit;
      end;
  Result := UNKNOWN_CHARSET;
end;

procedure TnsUniversalDetector.DoEnableCharset(Charset: eInternalCharsetID; SetEnabledTo: Boolean);
var
  i: integer;
begin
  if Charset = UNKNOWN_CHARSET then
    exit;
  for i := 0 to Pred(NUM_OF_CHARSET_PROBERS) do
    begin
      if (mCharSetProbers[i] is TnsGroupProber) then
        begin
          if TnsGroupProber(mCharSetProbers[i]).EnableCharset(Charset, SetEnabledTo) then
            exit;
        end;
      if (mCharSetProbers[i] is TMultiModelProber) then
        begin
          if TMultiModelProber(mCharSetProbers[i]).EnableCharset(Charset, SetEnabledTo) then
            exit;
        end
      else
        if (mCharSetProbers[i] is TCustomDetector) then
          begin
            if TCustomDetector(mCharSetProbers[i]).GetDetectedCharset = Charset then
              begin
                TCustomDetector(mCharSetProbers[i]).Enabled := SetEnabledTo;
                exit;
              end;
        end;
    end;

  if (mEscCharSetProber is TMultiModelProber) then
    begin
      if TMultiModelProber(mEscCharSetProber).EnableCharset(Charset, SetEnabledTo) then
        exit;
    end
  else
    if (mEscCharSetProber <> nil) and
       (mEscCharSetProber.GetDetectedCharset = Charset) then
      begin
        mEscCharSetProber.Enabled := SetEnabledTo;
        exit;
      end;

end;                                                                    

end.





