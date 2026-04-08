param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
$StressRoot = Join-Path $RepoRoot "test_vectors\restore\v1\stress_seed_v1"
$Manifest   = Join-Path $StressRoot "stress_seed_manifest.json"
$Matrix     = Join-Path $StressRoot "stress_case_matrix.txt"
if(-not (Test-Path -LiteralPath $StressRoot -PathType Container)){ Die ("MISSING_STRESS_ROOT: " + $StressRoot) }
if(-not (Test-Path -LiteralPath $Manifest -PathType Leaf)){ Die ("MISSING_STRESS_MANIFEST: " + $Manifest) }
if(-not (Test-Path -LiteralPath $Matrix -PathType Leaf)){ Die ("MISSING_STRESS_MATRIX: " + $Matrix) }
$m = ((Get-Content -Raw -LiteralPath $Manifest -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n") | ConvertFrom-Json)
$rows = @((Get-Content -LiteralPath $Matrix -Encoding UTF8) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
Write-Host "OK: TRIAD RESTORE STRESS SEED v1" -ForegroundColor Green
Write-Host ("snapshot_id: " + [string]$m.snapshot_id) -ForegroundColor Cyan
Write-Host ("payload_sha: " + [string]$m.payload_sha256) -ForegroundColor DarkGray
Write-Host ("case_count: " + $rows.Count) -ForegroundColor DarkGray
Write-Host "TRIAD_RESTORE_STRESS_SEED_V1_OK" -ForegroundColor Green
