$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $PSScriptRoot 'data'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

function Write-EncodedFile {
  param(
    [string]$Name,
    [int]$CodePage,
    [string]$Text,
    [bool]$WithBom = $false
  )

  $enc = [System.Text.Encoding]::GetEncoding($CodePage)
  $bytes = $enc.GetBytes($Text)
  if ($WithBom) {
    $bytes = $enc.GetPreamble() + $bytes
  }

  [System.IO.File]::WriteAllBytes((Join-Path $dataDir $Name), $bytes)
}

function Write-Utf32File {
  param(
    [string]$Name,
    [bool]$BigEndian,
    [bool]$WithBom,
    [string]$Text
  )

  $enc = New-Object System.Text.UTF32Encoding($BigEndian, $WithBom)
  $bytes = $enc.GetBytes($Text)
  if ($WithBom) {
    $bytes = $enc.GetPreamble() + $bytes
  }

  [System.IO.File]::WriteAllBytes((Join-Path $dataDir $Name), $bytes)
}

function Reverse-String {
  param(
    [string]$Text
  )

  $chars = $Text.ToCharArray()
  [array]::Reverse($chars)
  return (-join $chars)
}

function Write-Iso2022CnFixture {
  param(
    [string]$Name,
    [int]$RepeatCount = 120
  )

  $line = [byte[]](
    0x1B,0x24,0x29,0x41,0x0E,0x3D,0x3B,0x3B,0x3B,
    0x1B,0x24,0x29,0x47,0x47,0x28,0x5F,0x50,0x0F,
    0x20,0x49,0x53,0x4F,0x2D,0x32,0x30,0x32,0x32,0x2D,0x43,0x4E,
    0x0D,0x0A
  )

  $bytes = New-Object System.Collections.Generic.List[byte]
  for ($i = 0; $i -lt $RepeatCount; $i++) {
    $bytes.AddRange($line)
  }

  [System.IO.File]::WriteAllBytes((Join-Path $dataDir $Name), $bytes.ToArray())
}

$ascii = 'Plain ASCII detector sample. ' * 160
$russian = 'Это тест кодировки. Русский текст повторяется. ' * 160
$western = 'Cafe creme deja vu. Price 10 € and ellipsis … repeated with western punctuation. ' * 140
$westernNoC1 = 'Café crème déjà vu. Élève fiancé, garçon, Noël, über. À la carte. ' * 140
$greekIso = 'Αυτο ειναι δοκιμη ανιχνευσης κωδικοποιησης. Ελληνικο κειμενο επαναλαμβανεται. ' * 140
$greekWin = 'Αυτο ειναι δοκιμη με ευρω € και εισαγωγικα “κειμενο” που επαναλαμβανεται. ' * 140
$greekWinNoC1 = '΅ Ά Αυτη ειναι δοκιμη windows-1253 χωρις c1 bytes. Ελληνικο κειμενο επαναλαμβανεται. ' * 140
$hebrewWin = 'ם מטבע ₪ וסימנים מיוחדים שחוזרים על עצמם. ' * 140
$hebrewIsoVisual = (Reverse-String 'זהו מבחן לזיהוי קידוד. טקסט בעברית חוזר על עצמו. ') * 140
$japanese = 'これは文字コード判定のテストです。日本語の文章を繰り返します。東京、大阪、京都、漢字、かな、カナ。' * 140
$korean = '이것은 문자 인코딩 판별 테스트입니다. 한국어 문장을 반복합니다. 서울, 부산, 한국어. ' * 140
$tradChinese = '這是字元編碼偵測測試。繁體中文內容會重複出現。台北、高雄、漢字。' * 140
$simpChinese = '这是字符编码检测测试。简体中文内容会重复出现。北京、上海、汉字。' * 140
$gbChinese = '这是字符编码检测测试。简体中文内容会重复出现。华夏文明源远流长，江山如画。古语云：“𠀋者，仁之本也。” 观沧海之䶮䶮，望秋月之𣸣𣸣，万物生辉。' * 140

[System.IO.File]::WriteAllBytes((Join-Path $dataDir 'ascii.txt'), [System.Text.Encoding]::ASCII.GetBytes($ascii))
[System.IO.File]::WriteAllBytes((Join-Path $dataDir 'utf8-bom.txt'), [System.Text.Encoding]::UTF8.GetPreamble() + [System.Text.Encoding]::UTF8.GetBytes($russian))
[System.IO.File]::WriteAllBytes((Join-Path $dataDir 'utf8-nobom.txt'), [System.Text.Encoding]::UTF8.GetBytes($russian))
[System.IO.File]::WriteAllBytes((Join-Path $dataDir 'utf16le-bom.bin'), [System.Text.Encoding]::Unicode.GetPreamble() + [System.Text.Encoding]::Unicode.GetBytes($russian))
[System.IO.File]::WriteAllBytes((Join-Path $dataDir 'utf16be-bom.bin'), [System.Text.Encoding]::BigEndianUnicode.GetPreamble() + [System.Text.Encoding]::BigEndianUnicode.GetBytes($russian))
Write-Utf32File 'utf32le-bom.bin' $false $true $russian
Write-Utf32File 'utf32be-bom.bin' $true $true $russian
[System.IO.File]::WriteAllBytes((Join-Path $dataDir 'ucs4-2143-bom.bin'), [byte[]](0x00,0x00,0xFF,0xFE,0x00,0x00,0x00,0x41,0x00,0x00,0x00,0x42))
[System.IO.File]::WriteAllBytes((Join-Path $dataDir 'ucs4-3412-bom.bin'), [byte[]](0xFE,0xFF,0x00,0x00,0x00,0x00,0x41,0x00,0x00,0x00,0x42,0x00))

Write-EncodedFile 'windows-1251.txt' 1251 $russian
Write-EncodedFile 'iso-8859-5.txt' 28595 $russian
Write-EncodedFile 'koi8-r.txt' 20866 $russian
Write-EncodedFile 'ibm866.txt' 866 $russian
Write-EncodedFile 'ibm855.txt' 855 $russian
Write-EncodedFile 'x-mac-cyrillic.txt' 10007 $russian
Write-EncodedFile 'windows-1252.txt' 1252 $western
Write-EncodedFile 'windows-1252-no-c1.txt' 1252 $westernNoC1
Write-EncodedFile 'iso-8859-1-like.txt' 28591 $westernNoC1
Write-EncodedFile 'iso-8859-7.txt' 28597 $greekIso
Write-EncodedFile 'windows-1253.txt' 1253 $greekWin
Write-EncodedFile 'windows-1253-no-c1.txt' 1253 $greekWinNoC1
Write-EncodedFile 'windows-1255.txt' 1255 $hebrewWin
Write-EncodedFile 'iso-8859-8.txt' 28598 $hebrewIsoVisual
Write-EncodedFile 'shift-jis.txt' 932 $japanese
Write-EncodedFile 'euc-jp.txt' 51932 $japanese
Write-EncodedFile 'iso-2022-jp.txt' 50222 $japanese
Write-EncodedFile 'euc-kr.txt' 51949 $korean
Write-EncodedFile 'iso-2022-kr.txt' 50225 $korean
Write-EncodedFile 'big5.txt' 950 $tradChinese
Write-EncodedFile 'hz-gb-2312.txt' 52936 $simpChinese
Write-EncodedFile 'gb18030.txt' 54936 $gbChinese
Write-Iso2022CnFixture 'iso-2022-cn.txt'

Get-ChildItem -Path $dataDir -File | Select-Object Name, Length | Sort-Object Name
