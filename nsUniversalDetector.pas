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

  TDbcsByteState = (
    dbsNone,
    dbsNeedTrail,
    dbsNeedThird,
    dbsNeedFourth
  );

  TObservedByteStats = record
    TotalByteCount: Integer;
    HighByteCount: Integer;
    OemArtByteCount: Integer;
    SeenBytes: set of Byte;
    OemArtDistinctCount, Oem850DistinctCount, Oem852DistinctCount: Integer;
    Oem850ByteCount: Integer;
    Oem852ByteCount: Integer;
    Oem858ByteCount: Integer;
    Win1250ByteCount: Integer;
    Koi8UByteCount: Integer;
    DbcsPairCount: Integer;
    Gb18030FourByteCount: Integer;
    DbcsConsumedHighByteCount: Integer;
    DbcsInvalidHighByteCount: Integer;
    DbcsByteState: TDbcsByteState;
    Utf8ValidSequenceCount: Integer;
    Utf8ConsumedHighByteCount: Integer;
    Utf8InvalidByteCount: Integer;
    Utf8ExpectedTrailByteCount: Integer;
    EvenZeroByteCount: Integer;
    OddZeroByteCount: Integer;
    Utf16FirstByte: Byte;
    Utf16LEHighSurrogate, Utf16BEHighSurrogate: Boolean;
    Utf16LEInvalid, Utf16BEInvalid: Boolean;
    Utf16LEControlCount, Utf16BEControlCount: Integer;

    procedure Reset;
    procedure Feed(Value: Byte);
    procedure FeedDbcsByte(Value: Byte);
    procedure FeedUtf8Byte(Value: Byte);
    procedure FeedUtf16Byte(Value: Byte);
    function IsValidUtf16(Charset: eInternalCharsetID): Boolean;
    function IsPlausibleUtf16Text(Charset: eInternalCharsetID): Boolean;
    function LooksLikeOemArt: Boolean;
    function DetectOemTextSignature: eInternalCharsetID;
    function LooksLikeDbcsText: Boolean;
    function LooksLikeUtf8Text: Boolean;
    function LooksLikeUtf16Text: Boolean;
    function LooksLikeStructuredMultiByteText: Boolean;
    function DetectUtf16TextSignature: eInternalCharsetID;
    function HasGb18030FourByteSequence: Boolean;
    function HasKoi8USignal: Boolean;
    function HasWin1250Signal: Boolean;
  end;

  TDisabledCharsetSet = set of eInternalCharsetID;

	TnsUniversalDetector  = class (TObject)
    protected
      mInputState: nsInputState;
      mDone: Boolean;
      mStart: Boolean;
      mPrefix: RawByteString;
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
  DBCS_MIN_PAIR_COUNT = 10;
  DBCS_MIN_CONSUMED_HIGH_RATIO: float = 0.95;
  DBCS_MAX_INVALID_HIGH_RATIO: float = 0.02;
  UTF8_MIN_SEQUENCE_COUNT = 6;
  UTF8_MIN_CONSUMED_HIGH_RATIO: float = 0.95;
  UTF8_MAX_INVALID_HIGH_RATIO: float = 0.02;
  UTF16_MIN_ZERO_RATIO: float = 0.20;
  UTF16_MIN_ZERO_PARITY_RATIO: float = 0.85;
  UTF16_MAX_CONTROL_RATIO: float = 0.02;

  AboutInfo: rAboutHolder = (
    MajorVersionNr: 0;
    MinorVersionNr: 2;
    BuildVersionNr: 6;
    About: 'Charset Detector Library. Copyright (C) 2006 - 2008, Nick Yakowlew. http://chsdet.sourceforge.net';
  );

function IsDbcsLeadByte(Value: Byte): Boolean; inline;
begin
  Result := (Value >= $81) and (Value <= $FE);
end;

function IsDbcsTrailByte(Value: Byte): Boolean; inline;
begin
  Result :=
    ((Value >= $40) and (Value <= $7E)) or
    ((Value >= $80) and (Value <= $FE));
end;

function IsGb18030DigitByte(Value: Byte): Boolean; inline;
begin
  Result := (Value >= $30) and (Value <= $39);
end;

function IsUtf8LeadByte(Value: Byte): Boolean; inline;
begin
  Result :=
    ((Value >= $C2) and (Value <= $DF)) or
    ((Value >= $E0) and (Value <= $EF)) or
    ((Value >= $F0) and (Value <= $F4));
end;

function Utf8TrailByteCount(Value: Byte): Integer; inline;
begin
  if (Value >= $C2) and (Value <= $DF) then
    Result := 1
  else if (Value >= $E0) and (Value <= $EF) then
    Result := 2
  else if (Value >= $F0) and (Value <= $F4) then
    Result := 3
  else
    Result := 0;
end;

function IsUtf8TrailByte(Value: Byte): Boolean; inline;
begin
  Result := (Value >= $80) and (Value <= $BF);
end;

{ TObservedByteStats }

procedure TObservedByteStats.Reset;
begin
  TotalByteCount := 0;
  HighByteCount := 0;
  OemArtByteCount := 0;
  SeenBytes := [];
  OemArtDistinctCount := 0;
  Oem850DistinctCount := 0;
  Oem852DistinctCount := 0;
  Oem850ByteCount := 0;
  Oem852ByteCount := 0;
  Oem858ByteCount := 0;
  Win1250ByteCount := 0;
  Koi8UByteCount := 0;
  DbcsPairCount := 0;
  Gb18030FourByteCount := 0;
  DbcsConsumedHighByteCount := 0;
  DbcsInvalidHighByteCount := 0;
  DbcsByteState := dbsNone;
  Utf8ValidSequenceCount := 0;
  Utf8ConsumedHighByteCount := 0;
  Utf8InvalidByteCount := 0;
  Utf8ExpectedTrailByteCount := 0;
  EvenZeroByteCount := 0;
  OddZeroByteCount := 0;
  Utf16FirstByte := 0;
  Utf16LEHighSurrogate := False;
  Utf16BEHighSurrogate := False;
  Utf16LEInvalid := False;
  Utf16BEInvalid := False;
  Utf16LEControlCount := 0;
  Utf16BEControlCount := 0;
end;

procedure TObservedByteStats.Feed(Value: Byte);
var
  ByteIndex: Integer;
begin
  Inc(TotalByteCount);
  ByteIndex := TotalByteCount - 1;

  if Value >= $80 then
    Inc(HighByteCount);

  if Value = 0 then
    if (ByteIndex mod 2) = 0 then
      Inc(EvenZeroByteCount)
    else
      Inc(OddZeroByteCount);

  if Value in [$87, $89, $97, $A2] then
  begin
    if not (Value in SeenBytes) then
      Inc(Oem850DistinctCount);
    Inc(Oem850ByteCount);
  end;
  if Value in [$86, $88, $8B, $94, $98, $A0, $A1, $A3, $A5, $A7, $A9, $AB,
    $B5, $BE, $D4, $D8] then
  begin
    if not (Value in SeenBytes) then
      Inc(Oem852DistinctCount);
    Inc(Oem852ByteCount);
  end;
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
    begin
      if not (Value in SeenBytes) then
        Inc(OemArtDistinctCount);
      Inc(OemArtByteCount);
    end;
  end;
  Include(SeenBytes, Value);

  FeedDbcsByte(Value);
  FeedUtf8Byte(Value);
  FeedUtf16Byte(Value);
end;

procedure TObservedByteStats.FeedDbcsByte(Value: Byte);
var
  Reprocess: Boolean;
begin
  repeat
    Reprocess := False;

    case DbcsByteState of
      dbsNone:
        begin
          if IsDbcsLeadByte(Value) then
            DbcsByteState := dbsNeedTrail
          else if Value >= $80 then
            Inc(DbcsInvalidHighByteCount);
        end;

      dbsNeedTrail:
        begin
          if IsDbcsTrailByte(Value) then
          begin
            Inc(DbcsPairCount);
            Inc(DbcsConsumedHighByteCount);
            if Value >= $80 then
              Inc(DbcsConsumedHighByteCount);
            DbcsByteState := dbsNone;
          end
          else if IsGb18030DigitByte(Value) then
            DbcsByteState := dbsNeedThird
          else
          begin
            Inc(DbcsInvalidHighByteCount);
            DbcsByteState := dbsNone;
            Reprocess := Value >= $80;
          end;
        end;

      dbsNeedThird:
        begin
          if IsDbcsLeadByte(Value) then
            DbcsByteState := dbsNeedFourth
          else
          begin
            Inc(DbcsInvalidHighByteCount);
            DbcsByteState := dbsNone;
            Reprocess := Value >= $80;
          end;
        end;

      dbsNeedFourth:
        begin
          if IsGb18030DigitByte(Value) then
          begin
            Inc(Gb18030FourByteCount);
            Inc(DbcsConsumedHighByteCount, 2);
            DbcsByteState := dbsNone;
          end
          else
          begin
            Inc(DbcsInvalidHighByteCount);
            DbcsByteState := dbsNone;
            Reprocess := Value >= $80;
          end;
        end;
    end;
  until not Reprocess;
end;

procedure TObservedByteStats.FeedUtf8Byte(Value: Byte);
begin
  if Utf8ExpectedTrailByteCount > 0 then
  begin
    if IsUtf8TrailByte(Value) then
    begin
      Inc(Utf8ConsumedHighByteCount);
      Dec(Utf8ExpectedTrailByteCount);
      if Utf8ExpectedTrailByteCount = 0 then
        Inc(Utf8ValidSequenceCount);
    end
    else
    begin
      Inc(Utf8InvalidByteCount);
      Utf8ExpectedTrailByteCount := 0;
      if Value >= $80 then
        FeedUtf8Byte(Value);
    end;
    Exit;
  end;

  if IsUtf8LeadByte(Value) then
  begin
    Inc(Utf8ConsumedHighByteCount);
    Utf8ExpectedTrailByteCount := Utf8TrailByteCount(Value);
  end
  else if Value >= $80 then
    Inc(Utf8InvalidByteCount);
end;

procedure ValidateUtf16Unit(Value: Word; var HighSurrogate, Invalid: Boolean);
begin
  if Invalid then
    Exit;
  if HighSurrogate then
  begin
    Invalid := (Value < $DC00) or (Value > $DFFF);
    HighSurrogate := False;
  end
  else if (Value >= $D800) and (Value <= $DBFF) then
    HighSurrogate := True
  else if (Value >= $DC00) and (Value <= $DFFF) then
    Invalid := True;
end;

procedure TObservedByteStats.FeedUtf16Byte(Value: Byte);
var
  LE, BE: Word;
  function IsTextControl(UnitValue: Word): Boolean;
  begin
    Result := ((UnitValue < $20) and not (UnitValue in [$09..$0D])) or
      ((UnitValue >= $7F) and (UnitValue <= $9F) and (UnitValue <> $85));
  end;
begin
  // TotalByteCount already includes this byte. Preserve alignment across Feed.
  if (TotalByteCount mod 2) <> 0 then
    Utf16FirstByte := Value
  else
  begin
    LE := Word(Utf16FirstByte) or (Word(Value) shl 8);
    BE := (Word(Utf16FirstByte) shl 8) or Word(Value);
    if IsTextControl(LE) then
      Inc(Utf16LEControlCount);
    if IsTextControl(BE) then
      Inc(Utf16BEControlCount);
    ValidateUtf16Unit(LE,
      Utf16LEHighSurrogate, Utf16LEInvalid);
    ValidateUtf16Unit(BE,
      Utf16BEHighSurrogate, Utf16BEInvalid);
  end;
end;

function TObservedByteStats.IsValidUtf16(Charset: eInternalCharsetID): Boolean;
begin
  Result := (TotalByteCount > 0) and ((TotalByteCount mod 2) = 0);
  if Charset = UTF16_LE_CHARSET then
    Result := Result and not Utf16LEInvalid and not Utf16LEHighSurrogate
  else if Charset = UTF16_BE_CHARSET then
    Result := Result and not Utf16BEInvalid and not Utf16BEHighSurrogate
  else
    Result := False;
end;

function TObservedByteStats.LooksLikeOemArt: Boolean;
begin
  Result :=
    (TotalByteCount >= OEM_ART_MIN_BYTES) and
    (HighByteCount > 0) and
    (OemArtDistinctCount >= 2) and
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

  if LooksLikeStructuredMultiByteText then
    Exit;

  if (Oem858ByteCount >= 4) and (Oem850ByteCount >= 20) and
     (Oem850DistinctCount >= 2) then
    Exit(IBM858_CHARSET);

  if (Oem852ByteCount >= 20) and (Oem852DistinctCount >= 2) then
    Exit(IBM852_CHARSET);

  if (Oem850ByteCount >= 20) and (Oem850DistinctCount >= 2) then
    Exit(IBM850_CHARSET);

  if Win1250ByteCount >= WINDOWS_1250_MIN_SIGNATURE_BYTES then
    Exit(WINDOWS_1250_CHARSET);
end;

function TObservedByteStats.LooksLikeDbcsText: Boolean;
var
  ConsumedHighRatio: float;
  InvalidHighRatio: float;
begin
  Result := False;

  if (TotalByteCount < LEGACY_MIN_BYTES) or
     (HighByteCount < LEGACY_MIN_HIGH_BYTES) or
     (DbcsPairCount < DBCS_MIN_PAIR_COUNT) then
    Exit;

  ConsumedHighRatio := DbcsConsumedHighByteCount / HighByteCount;
  InvalidHighRatio := DbcsInvalidHighByteCount / HighByteCount;

  Result :=
    (ConsumedHighRatio >= DBCS_MIN_CONSUMED_HIGH_RATIO) and
    (InvalidHighRatio <= DBCS_MAX_INVALID_HIGH_RATIO);
end;

function TObservedByteStats.LooksLikeUtf8Text: Boolean;
var
  ConsumedHighRatio: float;
  InvalidHighRatio: float;
begin
  Result := False;

  if (TotalByteCount < LEGACY_MIN_BYTES) or
     (HighByteCount < LEGACY_MIN_HIGH_BYTES) or
     (Utf8ValidSequenceCount < UTF8_MIN_SEQUENCE_COUNT) or
     (Utf8ExpectedTrailByteCount <> 0) then
    Exit;

  ConsumedHighRatio := Utf8ConsumedHighByteCount / HighByteCount;
  InvalidHighRatio := Utf8InvalidByteCount / HighByteCount;

  Result :=
    (ConsumedHighRatio >= UTF8_MIN_CONSUMED_HIGH_RATIO) and
    (InvalidHighRatio <= UTF8_MAX_INVALID_HIGH_RATIO);
end;

function TObservedByteStats.IsPlausibleUtf16Text(Charset: eInternalCharsetID): Boolean;
var
  Controls: Integer;
begin
  Result := False;
  if not IsValidUtf16(Charset) then
    Exit;
  if Charset = UTF16_LE_CHARSET then
    Controls := Utf16LEControlCount
  else
    Controls := Utf16BEControlCount;
  // Valid code units and zero parity alone also describe binary integer arrays.
  Result := Controls / (TotalByteCount div 2) <= UTF16_MAX_CONTROL_RATIO;
end;

function TObservedByteStats.LooksLikeUtf16Text: Boolean;
var
  ZeroByteCount: Integer;
  ZeroRatio: float;
  ZeroParityRatio: float;
begin
  Result := False;
  ZeroByteCount := EvenZeroByteCount + OddZeroByteCount;

  if (TotalByteCount < LEGACY_MIN_BYTES) or
     (ZeroByteCount = 0) then
    Exit;

  ZeroRatio := ZeroByteCount / TotalByteCount;
  if EvenZeroByteCount > OddZeroByteCount then
    ZeroParityRatio := EvenZeroByteCount / ZeroByteCount
  else
    ZeroParityRatio := OddZeroByteCount / ZeroByteCount;

  Result :=
    (ZeroRatio >= UTF16_MIN_ZERO_RATIO) and
    (ZeroParityRatio >= UTF16_MIN_ZERO_PARITY_RATIO);
  if OddZeroByteCount > EvenZeroByteCount then
    Result := Result and IsPlausibleUtf16Text(UTF16_LE_CHARSET)
  else
    Result := Result and IsPlausibleUtf16Text(UTF16_BE_CHARSET);
end;

function TObservedByteStats.LooksLikeStructuredMultiByteText: Boolean;
begin
  Result := LooksLikeDbcsText or LooksLikeUtf8Text or LooksLikeUtf16Text;
end;

function TObservedByteStats.DetectUtf16TextSignature: eInternalCharsetID;
begin
  if not LooksLikeUtf16Text then
    Exit(UNKNOWN_CHARSET);

  if OddZeroByteCount > EvenZeroByteCount then
    Result := UTF16_LE_CHARSET
  else
    Result := UTF16_BE_CHARSET;
end;

function TObservedByteStats.HasGb18030FourByteSequence: Boolean;
begin
  Result := Gb18030FourByteCount > 0;
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
  ProberConfidence, BestConfidence: float;
  LegacyCharset, Candidate, BestCharset: eInternalCharsetID;
  StructuredMultiByteText: Boolean;
  I: Integer;
begin
  if mDone then
    Exit;
  try
    if mStart and (Length(mPrefix) > 0) then
    begin
      mStart := False;
      CheckBOM(PAnsiChar(mPrefix), Length(mPrefix));
      if not ReportWithConfidence(CharsetFromBOM(mDetectedBOM), SURE_YES) then
        HandleData(PAnsiChar(mPrefix), Length(mPrefix));
      mPrefix := '';
    end;
    if not mGotData or (mDetectedCharset <> UNKNOWN_CHARSET) then
      Exit;

    // ASCII characters in UTF-16 contain no high bytes. Their zero-byte
    // evidence must be evaluated even when the input state is ePureAscii.
    if mObservedBytes.LooksLikeUtf16Text and
       ReportWithConfidence(mObservedBytes.DetectUtf16TextSignature,
         OEM_TEXT_CONFIDENCE) then
      Exit;

    case mInputState of
      eHighbyte:
        begin
          ProberConfidence := mCharSetProbers[3].GetConfidence;
          if (ProberConfidence > MINIMUM_THRESHOLD) and
             ReportWithConfidence(UTF8_CHARSET, ProberConfidence) then
            Exit;

          BestConfidence := 0.0;
          BestCharset := UNKNOWN_CHARSET;
          for I := 0 to Pred(NUM_OF_CHARSET_PROBERS) do
          begin
            ProberConfidence := mCharSetProbers[I].GetConfidence;
            Candidate := mCharSetProbers[I].GetDetectedCharset;
            if (Candidate = UNKNOWN_CHARSET) or
               (mCharSetProbers[I].GetState = psNotMe) then
              Continue;
            if (Candidate = KOI8_R_CHARSET) and mObservedBytes.HasKoi8USignal then
              Candidate := KOI8_U_CHARSET
            else if (Candidate = WINDOWS_1252_CHARSET) and mObservedBytes.HasWin1250Signal then
              Candidate := WINDOWS_1250_CHARSET;
            Candidate := NormalizeCharsetByObservedBytes(Candidate);
            if not IsCharsetEnabled(Candidate) then
              Continue;
            if (Candidate in [UTF16_LE_CHARSET, UTF16_BE_CHARSET]) and
               not mObservedBytes.IsPlausibleUtf16Text(Candidate) then
              Continue;
            if (Candidate = UTF8_CHARSET) and
               (mCharSetProbers[3].GetConfidence <= SURE_NO) then
              Continue;
            if ProberConfidence > BestConfidence then
            begin
              BestConfidence := ProberConfidence;
              BestCharset := Candidate;
            end;
          end;

          StructuredMultiByteText := mObservedBytes.LooksLikeStructuredMultiByteText;
          // Isolated OEM signature bytes must not override a stronger model
          // supported by the complete stream's character sequences.
          if not StructuredMultiByteText then
          begin
            if LooksLikeOemArt and (BestConfidence < OEM_ART_CONFIDENCE) and
               ReportWithConfidence(IBM437_CHARSET, OEM_ART_CONFIDENCE) then
              Exit;
            LegacyCharset := DetectLegacyByteSignature;
            if (LegacyCharset <> UNKNOWN_CHARSET) and
               (BestConfidence < OEM_TEXT_CONFIDENCE) and
               ReportWithConfidence(LegacyCharset, OEM_TEXT_CONFIDENCE) then
              Exit;
          end;
          if BestConfidence > MINIMUM_THRESHOLD then
            ReportWithConfidence(BestCharset, BestConfidence);
        end;
      eEscAscii:
        begin
          ProberConfidence := mEscCharSetProber.GetConfidence;
          ReportWithConfidence(mEscCharSetProber.GetDetectedCharset, ProberConfidence);
        end;
    else
      ReportWithConfidence(PURE_ASCII_CHARSET, SURE_YES);
    end;
  finally
    mDone := True;
  end;
end;

function TnsUniversalDetector.HandleData(aBuf: PAnsiChar; aLen: integer): nsResult;
var
  i: integer;
  st: eProbingState;
  DetectedCharset: eInternalCharsetID;
  DetectedConfidence: float;
  PrefixCount: Integer;
  PrefixPart: RawByteString;
  ReplayTilde: Boolean;
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
  if aLen <= 0 then
    Exit(NS_OK);
  if aLen > 0 then
	  mGotData := TRUE;

  (*If the data starts with BOM, we know it is Unicode*)
  if mStart then
    begin
      PrefixCount := 4 - Length(mPrefix);
      if PrefixCount > aLen then
        PrefixCount := aLen;
      SetString(PrefixPart, aBuf, PrefixCount);
      mPrefix := mPrefix + PrefixPart;
      Inc(aBuf, PrefixCount);
      Dec(aLen, PrefixCount);
      if Length(mPrefix) < 4 then
        Exit(NS_OK);
      mStart := FALSE;
      CheckBOM(PAnsiChar(mPrefix), Length(mPrefix));
      if ReportWithConfidence(CharsetFromBOM(mDetectedBOM), SURE_YES) then
        begin
          mDone := TRUE;
          Result := NS_OK;
          exit;
        end;
      // Keep the first caller-supplied block intact. Splitting it internally
      // can discard the ASCII prefix of a mixed-script word in SBCS filtering.
      SetString(PrefixPart, aBuf, aLen);
      mPrefix := mPrefix + PrefixPart;
      Result := HandleData(PAnsiChar(mPrefix), Length(mPrefix));
      mPrefix := '';
      Exit;
    end; {if mStart}

  ReplayTilde := (mInputState = ePureAscii) and (mLastChar = '~') and
    (aBuf[0] = '{');
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

      // ASCII is strictly seven-bit; A0 (NBSP in several code pages) is not ASCII.
      if Byte(aBuf[i]) >= $80 then
        begin
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

  // SBCS needs ASCII-only blocks too: their last word can acquire a high byte
  // in a later block. Its streaming filter discards completed English words.
  mCharSetProbers[1].HandleData(aBuf, aLen);
  case mInputState of
    eEscAscii:
      begin
        {$ifdef DEBUG_chardet}
        AddDump('Universal detector - Escape Detector started');
        {$endif}
        if ReplayTilde then
          mEscCharSetProber.HandleData('~', 1);
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
          // Statistical choices remain provisional until DataEnd. A later
          // block may change the language score, byte order or GB18030 family.
          if i = 0 then
            mCharSetProbers[3].HandleData(aBuf, aLen);
          if (i <> 3) and (i <> 1) then
            mCharSetProbers[i].HandleData(aBuf, aLen);
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
  if (NormalizedCharset = UTF8_CHARSET) and
     (mDetectedBOM = BOM_Not_Found) and
     (mCharSetProbers[3].GetConfidence <= SURE_NO) then
    Exit(False);
  if (mDetectedBOM = BOM_Not_Found) and
     (NormalizedCharset in [UTF16_LE_CHARSET, UTF16_BE_CHARSET]) and
     not mObservedBytes.IsPlausibleUtf16Text(NormalizedCharset) then
    Exit;
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
  mPrefix := '';
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

  if (Charset = GB18030_CHARSET) and
     IsCharsetEnabled(GBK_CHARSET) and
     mObservedBytes.LooksLikeDbcsText and
     (not mObservedBytes.HasGb18030FourByteSequence) then
    begin
      Result := GBK_CHARSET;
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





