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
// $Id: chsd_dll_intf.pas,v 1.3 2008/06/22 09:04:21 ya_nick Exp $

unit chsd_dll_intf;

interface

const
  NS_OK = 0;
  NS_ERROR_OUT_OF_MEMORY = $8007000e;

type
	rCharsetInfo = record
  	Name: PAnsiChar;
    CodePage: integer;
    Language: PAnsiChar;
  end;
	prCharsetInfo = ^rCharsetInfo;

  rAboutHolder = record
    MajorVersionNr: Cardinal;
    MinorVersionNr: Cardinal;
    BuildVersionNr: Cardinal;
    About: PAnsiChar;
  end;

  eBOMKind =(
    BOM_Not_Found,
    BOM_UCS4_BE,    // 00 00 FE FF           UCS-4,    big-endian machine    (1234 order)
    BOM_UCS4_LE,    // FF FE 00 00           UCS-4,    little-endian machine (4321 order)
    BOM_UCS4_2143,  // 00 00 FF FE           UCS-4,    unusual octet order   (2143)
    BOM_UCS4_3412,  // FE FF 00 00           UCS-4,    unusual octet order   (3412)
    BOM_UTF16_BE,   // FE FF ## ##           UTF-16,   big-endian
    BOM_UTF16_LE,   // FF FE ## ##           UTF-16,   little-endian
    BOM_UTF8        // EF BB BF              UTF-8
  );

const
  CharsetDetectorLibrary = 'chsdet.dll';

	procedure chsd_Reset; stdcall; external CharsetDetectorLibrary;
  function chsd_HandleData(aBuf: PAnsiChar; aLen: integer): integer; stdcall; external CharsetDetectorLibrary;
  function chsd_Done: Boolean; stdcall; external CharsetDetectorLibrary;
  procedure chsd_DataEnd; stdcall; external CharsetDetectorLibrary;
  function chsd_GetDetectedCharset: rCharsetInfo; stdcall; external CharsetDetectorLibrary;
  function chsd_GetKnownCharsets(var KnownCharsets: PAnsiChar): Integer; stdcall; external CharsetDetectorLibrary;
  procedure chsd_GetAbout(var About: rAboutHolder); stdcall; external CharsetDetectorLibrary;
  function chsd_GetDetectedBOM: eBOMKind; stdcall; external CharsetDetectorLibrary;
  procedure chsd_DisableCharsetCP(CodePage: integer); stdcall; external CharsetDetectorLibrary;

implementation

end.
