param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$BaseManifest,
  [Parameter(Mandatory=$true)][string]$CompareManifest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

if(-not (Test-Path $BaseManifest)){ Die ("BASE_MANIFEST_NOT_FOUND: " + $BaseManifest) }
if(-not (Test-Path $CompareManifest)){ Die ("COMPARE_MANIFEST_NOT_FOUND: " + $CompareManifest) }

$base = Get-Content $BaseManifest -Raw | ConvertFrom-Json
$comp = Get-Content $CompareManifest -Raw | ConvertFrom-Json

if($base.root_hash -eq $comp.root_hash){
  Write-Host "VERIFY_RESULT: IDENTICAL"
  Write-Host ("ROOT_HASH: " + $base.root_hash)
  Write-Host "TRIAD_VERIFY_V1_OK"
  exit 0
}

Write-Host "VERIFY_RESULT: MISMATCH"
Write-Host ("BASE_ROOT: " + $base.root_hash)
Write-Host ("COMPARE_ROOT: " + $comp.root_hash)

# optional: quick signal counts
$baseCount = $base.entry_count
$compCount = $comp.entry_count

Write-Host ("BASE_COUNT: " + $baseCount)
Write-Host ("COMPARE_COUNT: " + $compCount)

Write-Host "TRIAD_VERIFY_V1_FAIL"
exit 1
