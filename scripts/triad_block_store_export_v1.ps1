param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$InputDir,
  [Parameter(Mandatory=$true)][string]$BlockmapManifest,
  [Parameter(Mandatory=$true)][string]$OutputStoreDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

if(-not (Test-Path $InputDir -PathType Container)){ Die ("INPUT_DIR_NOT_FOUND: " + $InputDir) }
if(-not (Test-Path $BlockmapManifest -PathType Leaf)){ Die ("BLOCKMAP_MANIFEST_NOT_FOUND: " + $BlockmapManifest) }
if(Test-Path $OutputStoreDir){ Die ("OUTPUT_STORE_ALREADY_EXISTS: " + $OutputStoreDir) }

$InputDir = (Resolve-Path $InputDir).Path

function Get-Sha256Hex([byte[]]$Bytes){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
  } finally {
    $sha.Dispose()
  }
  return ([System.BitConverter]::ToString($hash)).Replace("-","").ToLowerInvariant()
}

$manifest = Get-Content $BlockmapManifest -Raw | ConvertFrom-Json

New-Item -ItemType Directory -Force -Path $OutputStoreDir | Out-Null
$blocksDir = Join-Path $OutputStoreDir "blocks"
New-Item -ItemType Directory -Force -Path $blocksDir | Out-Null

$written = 0

foreach($file in $manifest.files){
  $sourcePath = Join-Path $InputDir $file.path
  if(-not (Test-Path $sourcePath -PathType Leaf)){ Die ("SOURCE_FILE_MISSING: " + $sourcePath) }

  $fs = [System.IO.File]::OpenRead($sourcePath)
  try {
    foreach($b in $file.blocks){
      $outPath = Join-Path $blocksDir ($b.sha256 + ".blk")
      if(Test-Path $outPath -PathType Leaf){ continue }

      $fs.Seek([int64]$b.offset, [System.IO.SeekOrigin]::Begin) | Out-Null

      $buffer = New-Object byte[] ([int]$b.size)
      $read = $fs.Read($buffer, 0, $buffer.Length)
      if($read -ne [int]$b.size){ Die ("BLOCK_READ_MISMATCH: " + $file.path + "@" + [string]$b.offset) }

      $sha = Get-Sha256Hex $buffer
      if($sha -ne [string]$b.sha256){ Die ("BLOCK_HASH_MISMATCH: " + $file.path + "@" + [string]$b.offset) }

      [System.IO.File]::WriteAllBytes($outPath, $buffer)
      $written += 1
    }
  }
  finally {
    $fs.Dispose()
  }
}

Copy-Item -LiteralPath $BlockmapManifest -Destination (Join-Path $OutputStoreDir "blockmap_dir_manifest.json") -Force

Write-Host ("STORE_DIR: " + $OutputStoreDir)
Write-Host ("BLOCKS_WRITTEN: " + $written)
Write-Host ("UNIQUE_BLOCK_COUNT: " + $manifest.unique_block_count)
Write-Host "TRIAD_BLOCK_STORE_EXPORT_V1_OK"
