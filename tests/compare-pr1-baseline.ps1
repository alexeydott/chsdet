# Compare identical harness/corpus against original main and the current checkout.
# Requires git, Delphi and configured DUnitX paths. Run run-range-matrix.ps1 first.
[CmdletBinding()]
param([string]$BaselineRef = '4660893fb7966f78982ef23fb2fb92215499cbec',
      [string]$Compiler32 = 'dcc32', [string]$Compiler64 = 'dcc64')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('chsdet-baseline-' + [guid]::NewGuid().ToString('N'))
Push-Location $root
try {
  & git worktree add --detach $tempRoot $BaselineRef
  if ($LASTEXITCODE -ne 0) { throw 'Cannot create isolated baseline worktree' }
  # Keep harness identical; production units come exclusively from BaselineRef.
  Copy-Item (Join-Path $root 'ChsDetTests.dpr') $tempRoot -Force
  Copy-Item (Join-Path $root 'tests/*') (Join-Path $tempRoot 'tests') -Recurse -Force
  Push-Location $tempRoot
  try {
    foreach ($target in @(@('Win32', $Compiler32), @('Win64', $Compiler64))) {
      $out = Join-Path $root ('build-range/' + $target[0] + '/baseline')
      New-Item -ItemType Directory -Force -Path $out | Out-Null
      & $target[1] -B '-$R-' '-$Q-' "-E$out" "-N0$out" '-I.;tests' '-U.;tests' tests/ChsDetSnapshot.dpr 2>&1 |
        Tee-Object (Join-Path $out 'compile-snapshot.log')
      if ($LASTEXITCODE -ne 0) { throw 'Baseline snapshot build failed' }
      $snapshot = Join-Path $out 'snapshot.tsv'
      & (Join-Path $out 'ChsDetSnapshot.exe') $snapshot
      if ($LASTEXITCODE -ne 0) { throw 'Baseline snapshot execution failed' }
      $fixedSnapshot = Join-Path $root ('build-range/' + $target[0] + '/Rminus-Qminus/snapshot.tsv')
      if (!(Test-Path $fixedSnapshot)) { throw 'Run run-range-matrix.ps1 first' }
      if ((Get-Content -Raw $snapshot) -cne (Get-Content -Raw $fixedSnapshot)) {
        throw "Recognition differs from original main: $($target[0])"
      }
      # Same test sources, old production units: failure must be runtime range error.
      & $target[1] -B '-$R+' '-$Q+' "-E$out" "-N0$out" '-I.;tests' '-U.;tests' ChsDetTests.dpr 2>&1 |
        Tee-Object (Join-Path $out 'compile-tests.log')
      if ($LASTEXITCODE -ne 0) { throw 'Baseline tests did not compile; no red evidence' }
      $report = Join-Path $out 'dunitx-results.xml'
      if (Test-Path $report) { Remove-Item $report }
      & (Join-Path $out 'ChsDetTests.exe') --hidebanner --consolemode:Quiet 2>&1 |
        Tee-Object (Join-Path $out 'tests.log')
      if ($LASTEXITCODE -eq 0) { throw 'Old version unexpectedly passed: inspect reproduction' }
      [xml]$xml = Get-Content -Raw (Join-Path $out 'dunitx-results.xml')
      foreach ($method in @('RawTablesDoNotRequireDynamicArrayHeaders',
                            'PackedNibblesIncludeHighBitAndWordBoundary',
                            'DistributionChecksActualLengthBeforeReading')) {
        $failed = @($xml.SelectNodes('//test-case') | Where-Object {
          ($_.name -match $method -or $_.fullname -match $method) -and
          $_.OuterXml -match 'Range check error'
        })
        if ($failed.Count -ne 1) { throw "Target range error not established: $method" }
      }
    }
    Write-Host 'Baseline recognition matches; three deterministic old-version range failures established on both targets.'
  } finally { Pop-Location }
} finally {
  Pop-Location
  # Only remove the unique worktree created above; logs stay in build-range.
  if (Test-Path $tempRoot) {
    & git -C $root worktree remove --force $tempRoot
    if ($LASTEXITCODE -ne 0) { Write-Warning "Could not remove $tempRoot" }
  }
}
