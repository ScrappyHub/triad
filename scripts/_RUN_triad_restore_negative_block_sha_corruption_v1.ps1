param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Ensure-Dir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ Die "ENSURE_DIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Sha256HexFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [System.IO.File]::OpenRead($Path)
    try { $hash = $sha.ComputeHash($fs) } finally { $fs.Dispose() }
  } finally { $sha.Dispose() }
  return ([BitConverter]::ToString($hash)).Replace("-","").ToLowerInvariant()
}

$RepoRoot = (Resolve-Path $RepoRoot).Path

$PosRoot = Join-Path $RepoRoot "test_vectors\restore\v1\positive\locked_green_restore_vector"
$NegRoot = Join-Path $RepoRoot "test_vectors\restore\v1\negative\block_sha_corruption_invalid_v1"

if(-not (Test-Path $PosRoot)){ Die "MISSING_POS_VECTOR" }

Remove-Item -Recurse -Force $NegRoot -ErrorAction SilentlyContinue
Ensure-Dir $NegRoot

Copy-Item "$PosRoot\*" $NegRoot -Recurse -Force

$Manifest = Join-Path $NegRoot "snapshot_v1\snapshot.tree.manifest.json"
$m = Get-Content -Raw $Manifest | ConvertFrom-Json

$payload = $m.entries | Where-Object { $_.path -eq "payload.bin" }
$block = $payload.blocks[0]

$blockPath = Join-Path $NegRoot ("snapshot_v1\" + $block.path.Replace("/","\"))

$expected = $block.sha256
$before = Sha256HexFile $blockPath

if($before -ne $expected){ Die "PRECHECK_SHA_MISMATCH" }

$bytes = [System.IO.File]::ReadAllBytes($blockPath)
$bytes[0] = $bytes[0] -bxor 1
[System.IO.File]::WriteAllBytes($blockPath,$bytes)

$after = Sha256HexFile $blockPath

if($after -eq $expected){ Die "CORRUPTION_FAILED" }

Write-Host "NEG_VECTOR_OK" -ForegroundColor Green
Write-Host ("CORRUPTED_BLOCK: " + $block.path)
Write-Host ("EXPECTED: " + $expected)
Write-Host ("ACTUAL: " + $after)