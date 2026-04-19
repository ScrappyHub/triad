param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$StoreDir,
  [Parameter(Mandatory=$true)][string]$OutputDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

if(-not (Test-Path $StoreDir -PathType Container)){ Die ("STORE_DIR_NOT_FOUND: " + $StoreDir) }
if(Test-Path $OutputDir){ Die ("OUTPUT_DIR_ALREADY_EXISTS: " + $OutputDir) }

$StoreDir = (Resolve-Path $StoreDir).Path
$ManifestPath = Join-Path $StoreDir "blockmap_dir_manifest.json"
$BlocksDir = Join-Path $StoreDir "blocks"

if(-not (Test-Path $ManifestPath -PathType Leaf)){ Die ("MANIFEST_NOT_FOUND: " + $ManifestPath) }
if(-not (Test-Path $BlocksDir -PathType Container)){ Die ("BLOCKS_DIR_NOT_FOUND: " + $BlocksDir) }

function Ensure-Dir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ Die "ENSURE_DIR_EMPTY" }
  if(-not (Test-Path $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Get-Sha256Hex([byte[]]$Bytes){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
  } finally {
    $sha.Dispose()
  }
  return ([System.BitConverter]::ToString($hash)).Replace("-","").ToLowerInvariant()
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json

Ensure-Dir $OutputDir

$restoredFiles = 0
$restoredDirs = 0

if($manifest.PSObject.Properties.Name -contains "dirs"){
  foreach($dir in $manifest.dirs){
    $targetDir = Join-Path $OutputDir $dir.path
    Ensure-Dir $targetDir
    [System.IO.Directory]::SetLastWriteTimeUtc($targetDir, [datetime]::Parse($dir.last_write).ToUniversalTime())
    $restoredDirs += 1
  }
}

foreach($file in $manifest.files){
  $targetPath = Join-Path $OutputDir $file.path
  $targetDir = Split-Path -Parent $targetPath
  if($targetDir){
    Ensure-Dir $targetDir
  }

  $outFs = [System.IO.File]::Create($targetPath)
  try {
    foreach($b in $file.blocks){
      $blkPath = Join-Path $BlocksDir ($b.sha256 + ".blk")
      if(-not (Test-Path $blkPath -PathType Leaf)){ Die ("BLOCK_FILE_MISSING: " + $blkPath) }

      $bytes = [System.IO.File]::ReadAllBytes($blkPath)
      if($bytes.Length -ne [int]$b.size){ Die ("BLOCK_SIZE_MISMATCH: " + $blkPath) }

      $sha = Get-Sha256Hex $bytes
      if($sha -ne [string]$b.sha256){ Die ("BLOCK_HASH_MISMATCH: " + $blkPath) }

      $outFs.Write($bytes, 0, $bytes.Length)
    }
  }
  finally {
    $outFs.Dispose()
  }

  if($file.PSObject.Properties.Name -contains "last_write"){
    [System.IO.File]::SetLastWriteTimeUtc($targetPath, [datetime]::Parse($file.last_write).ToUniversalTime())
  }

  $restoredFiles += 1
}

Write-Host ("OUTPUT_DIR: " + $OutputDir)
Write-Host ("RESTORED_FILES: " + $restoredFiles)
Write-Host ("RESTORED_DIRS: " + $restoredDirs)
Write-Host "TRIAD_RESTORE_DIR_FROM_BLOCK_STORE_V1_OK"
