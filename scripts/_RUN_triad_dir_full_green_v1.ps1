param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$InputDir = ".\scripts\_work\triad_archive_selftest_v1\input"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

$RepoRoot = (Resolve-Path $RepoRoot).Path
if([System.IO.Path]::IsPathRooted($InputDir)){
  $InputDir = (Resolve-Path $InputDir).Path
} else {
  $InputDir = (Resolve-Path (Join-Path $RepoRoot $InputDir)).Path
}
$WorkRoot = Join-Path $RepoRoot "scripts\_work\triad_dir_full_green_v1"

$Blockmap = Join-Path $WorkRoot "blockmap_dir.json"
$StoreDir = Join-Path $WorkRoot "block_store"
$RestoreDir = Join-Path $WorkRoot "restored"
$OrigCapture = Join-Path $WorkRoot "orig_capture_v2.json"
$RestoredCapture = Join-Path $WorkRoot "restored_capture_v2.json"

if(Test-Path $WorkRoot){
  Remove-Item $WorkRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

function Run-Step([string]$Script,[hashtable]$Params){
  if(-not (Test-Path $Script -PathType Leaf)){ Die ("SCRIPT_NOT_FOUND: " + $Script) }
  & $Script @Params
}

$Scripts = Join-Path $RepoRoot "scripts"

Run-Step (Join-Path $Scripts "triad_blockmap_dir_v1.ps1") @{
  RepoRoot = $RepoRoot
  InputDir = $InputDir
  OutputManifest = $Blockmap
}

Run-Step (Join-Path $Scripts "triad_block_store_export_v1.ps1") @{
  RepoRoot = $RepoRoot
  InputDir = $InputDir
  BlockmapManifest = $Blockmap
  OutputStoreDir = $StoreDir
}

Run-Step (Join-Path $Scripts "triad_restore_dir_from_block_store_v1.ps1") @{
  RepoRoot = $RepoRoot
  StoreDir = $StoreDir
  OutputDir = $RestoreDir
}

Run-Step (Join-Path $Scripts "triad_capture_v2.ps1") @{
  RepoRoot = $RepoRoot
  InputDir = $InputDir
  OutputManifest = $OrigCapture
}

Run-Step (Join-Path $Scripts "triad_capture_v2.ps1") @{
  RepoRoot = $RepoRoot
  InputDir = $RestoreDir
  OutputManifest = $RestoredCapture
}

Run-Step (Join-Path $Scripts "triad_verify_v1.ps1") @{
  RepoRoot = $RepoRoot
  BaseManifest = $OrigCapture
  CompareManifest = $RestoredCapture
}

Write-Host ("WORK_ROOT: " + $WorkRoot)
Write-Host "TRIAD_DIR_FULL_GREEN"
