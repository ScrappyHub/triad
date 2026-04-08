param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
function Die([string]$Message){ throw $Message }
function Read-Utf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  return (Get-Content -Raw -LiteralPath $Path -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$NegRoot = Join-Path $RepoRoot "test_vectors\restore\v1\negative\naive_unique_concat_invalid_v1"
$ManifestPath = Join-Path $NegRoot "negative_vector_manifest.json"
if(-not (Test-Path -LiteralPath $NegRoot -PathType Container)){ Die ("MISSING_NEG_VECTOR_ROOT: " + $NegRoot) }
if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){ Die ("MISSING_NEG_VECTOR_MANIFEST: " + $ManifestPath) }
$m = Read-Utf8 $ManifestPath | ConvertFrom-Json
if([string]$m.schema -ne "triad.restore.negative.vector.v1"){ Die "NEG_VECTOR_SCHEMA_MISMATCH" }
if([string]$m.expected_result -ne "FAIL"){ Die "NEG_VECTOR_EXPECTED_RESULT_MISMATCH" }
if([string]$m.naive_output_sha256 -eq [string]$m.expected_payload_sha256){ Die "NEG_VECTOR_UNEXPECTED_SHA_MATCH" }
if([int64]$m.naive_output_length -eq [int64]$m.expected_payload_length){ Die "NEG_VECTOR_UNEXPECTED_LEN_MATCH" }
Write-Host "OK: TRIAD NEGATIVE VECTOR v1" -ForegroundColor Green
Write-Host ("vector_id: " + [string]$m.vector_id) -ForegroundColor Cyan
Write-Host ("expected_result: " + [string]$m.expected_result) -ForegroundColor DarkGray
Write-Host "TRIAD_NEGATIVE_VECTOR_NAIVE_UNIQUE_CONCAT_V1_SELFTEST_OK" -ForegroundColor Green
