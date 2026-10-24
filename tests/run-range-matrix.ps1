# Run after rsvars.bat; dcc32/dcc64 and DUnitX must be on the configured paths.
[CmdletBinding()]
param([string]$Compiler32 = 'dcc32', [string]$Compiler64 = 'dcc64')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
  foreach ($target in @(@('Win32', $Compiler32), @('Win64', $Compiler64))) {
    $targetSnapshot = $null
    foreach ($mode in @(@('Rplus-Qplus', '-$R+', '-$Q+'), @('Rminus-Qminus', '-$R-', '-$Q-'),
                        @('Rplus-Qminus', '-$R+', '-$Q-'), @('Rminus-Qplus', '-$R-', '-$Q+'))) {
      $out = Join-Path $root ('build-range/' + $target[0] + '/' + $mode[0])
      New-Item -ItemType Directory -Force -Path $out | Out-Null
      # -B is essential: directives on the DPR alone do not recompile old DCUs.
      & $target[1] -B $mode[1] $mode[2] "-E$out" "-N0$out" '-I.;tests' '-U.;tests' ChsDetTests.dpr 2>&1 |
        Tee-Object (Join-Path $out 'compile-tests.log')
      if ($LASTEXITCODE -ne 0) { throw "Test build failed: $out" }
      $report = Join-Path $out 'dunitx-results.xml'
      if (Test-Path $report) { Remove-Item $report }
      & (Join-Path $out 'ChsDetTests.exe') --hidebanner --consolemode:Quiet 2>&1 |
        Tee-Object (Join-Path $out 'tests.log')
      if ($LASTEXITCODE -ne 0) { throw "Tests failed: $out" }
      if (!(Test-Path $report)) { throw "Missing DUnitX XML: $out" }
      [xml]$xml = Get-Content -Raw $report
      $cases = @($xml.SelectNodes('//test-case'))
      $tableCases = @($xml.SelectNodes('//test-suite[@name="TChsTableTests"]//test-case'))
      if ($tableCases.Count -lt 4) { throw "Table tests not discovered: $out" }
      if ($cases.Count -eq 0) { throw "No tests executed: $out" }
      foreach ($fixture in @(@('TChsRegressionTests', 12), @('TChsProberTests', 12),
                              @('TChsStreamingTests', 11))) {
        $required = @($xml.SelectNodes('//test-suite[@name="' + $fixture[0] + '"]//test-case'))
        if ($required.Count -lt $fixture[1]) { throw "Regression fixture not discovered: $($fixture[0]) in $out" }
      }
      foreach ($case in $cases) {
        if ($case.success -ne 'True' -and $case.result -ne 'Success' -and $case.result -ne 'Passed') {
          throw "Non-passing or ignored test: $($case.name) in $out"
        }
      }
      & $target[1] -B $mode[1] $mode[2] "-E$out" "-N0$out" '-I.;tests' '-U.;tests' tests/ChsDetSnapshot.dpr 2>&1 |
        Tee-Object (Join-Path $out 'compile-snapshot.log')
      if ($LASTEXITCODE -ne 0) { throw "Snapshot build failed: $out" }
      $snapshot = Join-Path $out 'snapshot.tsv'
      & (Join-Path $out 'ChsDetSnapshot.exe') $snapshot
      if ($LASTEXITCODE -ne 0) { throw "Snapshot failed: $out" }
      $content = Get-Content -Raw $snapshot
      if ($null -eq $targetSnapshot) { $targetSnapshot = $content }
      elseif ($content -cne $targetSnapshot) { throw "R/Q mode changed recognition: $out" }
    }
  }
  Write-Host 'All eight build/test configurations passed; snapshots match within each platform.'
  Write-Host 'Cross-platform confidence bits are retained for inspection, not asserted identical.'
} finally { Pop-Location }

