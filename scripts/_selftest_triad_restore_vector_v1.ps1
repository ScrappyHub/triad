param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$Message){ throw $Message }

function Read-Utf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  return (Get-Content -Raw -LiteralPath $Path -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
}

function Sha256HexFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [System.IO.File]::OpenRead($Path)
    try { $hash = $sha.ComputeHash($fs) } finally { $fs.Dispose() }
  } finally {
    $sha.Dispose()
  }
  return ([BitConverter]::ToString($hash)).Replace("-","").ToLowerInvariant()
}

function PropOf($Object,[string]$Name){
  if($null -eq $Object){ return $null }
  $prop = $Object.PSObject.Properties[$Name]
  if($null -eq $prop){ return $null }
  return $prop.Value
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$VectorRoot = Join-Path $RepoRoot "test_vectors\restore\v1\positive\locked_green_restore_vector"
$ManifestPath = Join-Path $VectorRoot "snapshot_v1\snapshot.tree.manifest.json"
$VectorManifestPath = Join-Path $VectorRoot "vector_manifest.json"
$RestoredPath = Join-Path $VectorRoot "restored.bin"
$HashFile = Join-Path $VectorRoot "sha256sums.txt"

if(-not (Test-Path -LiteralPath $VectorRoot -PathType Container)){ Die ("MISSING_VECTOR_ROOT: " + $VectorRoot) }
if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){ Die ("MISSING_MANIFEST: " + $ManifestPath) }
if(-not (Test-Path -LiteralPath $VectorManifestPath -PathType Leaf)){ Die ("MISSING_VECTOR_MANIFEST: " + $VectorManifestPath) }
if(-not (Test-Path -LiteralPath $RestoredPath -PathType Leaf)){ Die ("MISSING_RESTORED_BIN: " + $RestoredPath) }
if(-not (Test-Path -LiteralPath $HashFile -PathType Leaf)){ Die ("MISSING_SHA256SUMS: " + $HashFile) }

$ManifestObj = Read-Utf8 $ManifestPath | ConvertFrom-Json
$VectorObj = Read-Utf8 $VectorManifestPath | ConvertFrom-Json
$Entries = @(@(PropOf $ManifestObj "entries"))
$PayloadEntry = $null
foreach($e in $Entries){
  if($null -eq $e){ continue }
  $type = [string](PropOf $e "type")
  $path = [string](PropOf $e "path")
  if($type -eq "file" -and $path -eq "payload.bin"){ $PayloadEntry = $e; break }
}
if($null -eq $PayloadEntry){ Die "VECTOR_SELFTEST_PAYLOAD_ENTRY_NOT_FOUND" }

$PayloadSha = [string](PropOf $PayloadEntry "sha256")
$PayloadLen = [int64](PropOf $PayloadEntry "length")
$PayloadBlocks = @(@(PropOf $PayloadEntry "blocks"))
$BlockCount = $PayloadBlocks.Count
$RestoredSha = Sha256HexFile $RestoredPath

if([string](PropOf $VectorObj "schema") -ne "triad.restore.vector.v1"){ Die "VECTOR_SCHEMA_MISMATCH" }
if([string](PropOf $VectorObj "snapshot_id") -ne [string](PropOf $ManifestObj "snapshot_id")){ Die "VECTOR_SNAPSHOT_ID_MISMATCH" }
if([string](PropOf $VectorObj "payload_sha256") -ne $PayloadSha){ Die "VECTOR_PAYLOAD_SHA_MISMATCH" }
if([int64](PropOf $VectorObj "payload_length") -ne $PayloadLen){ Die "VECTOR_PAYLOAD_LENGTH_MISMATCH" }
if([int64](PropOf $VectorObj "payload_block_count") -ne $BlockCount){ Die "VECTOR_BLOCK_COUNT_MISMATCH" }
if([string](PropOf $VectorObj "restored_bin_sha256") -ne $RestoredSha){ Die "VECTOR_RESTORED_SHA_FIELD_MISMATCH" }
if($RestoredSha -ne $PayloadSha){ Die "VECTOR_RESTORED_SHA_ACTUAL_MISMATCH" }

Write-Host "OK: TRIAD RESTORE VECTOR v1" -ForegroundColor Green
Write-Host ("snapshot_id: " + [string](PropOf $ManifestObj "snapshot_id")) -ForegroundColor Cyan
Write-Host ("payload_sha: " + $PayloadSha) -ForegroundColor DarkGray
Write-Host ("payload_len: " + $PayloadLen) -ForegroundColor DarkGray
Write-Host ("block_count: " + $BlockCount) -ForegroundColor DarkGray
Write-Host "TRIAD_RESTORE_VECTOR_V1_OK" -ForegroundColor Green
