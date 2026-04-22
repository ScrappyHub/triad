param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Command,

  [string]$InputDir,
  [string]$ArchiveDir,
  [string]$OutputDir,
  [string]$OutputManifest,

  [string]$InputPath,
  [string]$OutputPath,
  [string]$ManifestPath,
  [string]$TransformType,

  [string]$StoreDir,
  [string]$BaseManifest,
  [string]$CompareManifest,
  [string]$BlockmapManifest,
  [int]$BlockSize = 1048576
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

function Run($Script,$Params){
  if(-not (Test-Path -LiteralPath $Script -PathType Leaf)){
    throw ("SCRIPT_NOT_FOUND: " + $Script)
  }
  & $Script @Params
}

function Resolve-MaybeRelative([string]$Base,[string]$Value){
  if([string]::IsNullOrWhiteSpace($Value)){ return $Value }
  if([System.IO.Path]::IsPathRooted($Value)){ return $Value }
  return (Join-Path $Base $Value)
}

function Assert-ScriptSet([string[]]$Paths){
  foreach($p in $Paths){
    if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
      Die ("SCRIPT_MISSING: " + $p)
    }
  }
}

$RepoRoot = (Resolve-Path $RepoRoot).Path
$Scripts = Join-Path $RepoRoot "scripts"

$InputDir = Resolve-MaybeRelative $RepoRoot $InputDir
$ArchiveDir = Resolve-MaybeRelative $RepoRoot $ArchiveDir
$OutputDir = Resolve-MaybeRelative $RepoRoot $OutputDir
$OutputManifest = Resolve-MaybeRelative $RepoRoot $OutputManifest
$InputPath = Resolve-MaybeRelative $RepoRoot $InputPath
$OutputPath = Resolve-MaybeRelative $RepoRoot $OutputPath
$ManifestPath = Resolve-MaybeRelative $RepoRoot $ManifestPath
$StoreDir = Resolve-MaybeRelative $RepoRoot $StoreDir
$BaseManifest = Resolve-MaybeRelative $RepoRoot $BaseManifest
$CompareManifest = Resolve-MaybeRelative $RepoRoot $CompareManifest
$BlockmapManifest = Resolve-MaybeRelative $RepoRoot $BlockmapManifest

switch($Command){

  "version" {
    Write-Host "TRIAD_CLI_V1"
    return
  }

  "quick-check" {
    $required = @(
      (Join-Path $Scripts "triad_cli_v1.ps1"),
      (Join-Path $Scripts "_RUN_triad_dir_full_green_v1.ps1"),
      (Join-Path $Scripts "_RUN_triad_dir_release_green_v1.ps1"),
      (Join-Path $Scripts "triad_capture_v2.ps1"),
      (Join-Path $Scripts "triad_verify_v1.ps1"),
      (Join-Path $Scripts "triad_blockmap_dir_v1.ps1"),
      (Join-Path $Scripts "triad_block_store_export_v1.ps1"),
      (Join-Path $Scripts "triad_restore_dir_from_block_store_v1.ps1")
    )
    Assert-ScriptSet $required
    Write-Host "TRIAD_QUICK_CHECK_OK"
    return
  }

  "doctor" {
    Write-Host ("REPO_ROOT: " + $RepoRoot)
    Write-Host ("POWERSHELL: " + $PSVersionTable.PSVersion.ToString())
    Write-Host ("STRICT_MODE: Latest")
    if(-not (Test-Path -LiteralPath $Scripts -PathType Container)){ Die "SCRIPTS_DIR_MISSING" }

    $required = @(
      (Join-Path $Scripts "triad_cli_v1.ps1"),
      (Join-Path $Scripts "_RUN_triad_dir_full_green_v1.ps1"),
      (Join-Path $Scripts "_RUN_triad_dir_release_green_v1.ps1"),
      (Join-Path $Scripts "triad_capture_v2.ps1"),
      (Join-Path $Scripts "triad_verify_v1.ps1"),
      (Join-Path $Scripts "triad_blockmap_dir_v1.ps1"),
      (Join-Path $Scripts "triad_block_store_export_v1.ps1"),
      (Join-Path $Scripts "triad_restore_dir_from_block_store_v1.ps1"),
      (Join-Path $Scripts "_selftest_triad_dir_negative_missing_block_v1.ps1"),
      (Join-Path $Scripts "_selftest_triad_dir_negative_tampered_block_v1.ps1"),
      (Join-Path $Scripts "_selftest_triad_dir_negative_tampered_manifest_v1.ps1")
    )
    Assert-ScriptSet $required

    Write-Host ("FREEZE_DIR_EXISTS: " + (Test-Path -LiteralPath (Join-Path $RepoRoot "proofs\freeze")))
    Write-Host ("RECEIPTS_DIR_EXISTS: " + (Test-Path -LiteralPath (Join-Path $RepoRoot "proofs\receipts")))
    Write-Host "TRIAD_DOCTOR_OK"
    return
  }

  "verify-release" {
    Run (Join-Path $Scripts "_RUN_triad_full_green_v1.ps1") @{
      RepoRoot = $RepoRoot
    }
    return
  }

  "full-green" {
    Run (Join-Path $Scripts "_RUN_triad_dir_full_green_v1.ps1") @{
      RepoRoot = $RepoRoot
      InputDir = $(if($InputDir){ $InputDir } else { (Join-Path $RepoRoot "scripts\_work\triad_archive_selftest_v1\input") })
    }
    return
  }

  "release" {
    Run (Join-Path $Scripts "_RUN_triad_dir_release_green_v1.ps1") @{
      RepoRoot = $RepoRoot
      InputDir = $(if($InputDir){ $InputDir } else { (Join-Path $RepoRoot "scripts\_work\triad_archive_selftest_v1\input") })
    }
    return
  }

  "dir-full-green" {
    Run (Join-Path $Scripts "_RUN_triad_dir_full_green_v1.ps1") @{
      RepoRoot = $RepoRoot
      InputDir = $(if($InputDir){ $InputDir } else { (Join-Path $RepoRoot "scripts\_work\triad_archive_selftest_v1\input") })
    }
    return
  }

  "dir-blockmap" {
    if(-not $InputDir){ Die "MISSING: InputDir" }
    if(-not $OutputManifest){ Die "MISSING: OutputManifest" }

    Run (Join-Path $Scripts "triad_blockmap_dir_v1.ps1") @{
      RepoRoot = $RepoRoot
      InputDir = $InputDir
      OutputManifest = $OutputManifest
      BlockSize = $BlockSize
    }
    return
  }

  "dir-store-export" {
    if(-not $InputDir){ Die "MISSING: InputDir" }
    if(-not $BlockmapManifest){ Die "MISSING: BlockmapManifest" }
    if(-not $OutputDir){ Die "MISSING: OutputDir" }

    Run (Join-Path $Scripts "triad_block_store_export_v1.ps1") @{
      RepoRoot = $RepoRoot
      InputDir = $InputDir
      BlockmapManifest = $BlockmapManifest
      OutputStoreDir = $OutputDir
    }
    return
  }

  "dir-restore" {
    if(-not $StoreDir){ Die "MISSING: StoreDir" }
    if(-not $OutputDir){ Die "MISSING: OutputDir" }

    Run (Join-Path $Scripts "triad_restore_dir_from_block_store_v1.ps1") @{
      RepoRoot = $RepoRoot
      StoreDir = $StoreDir
      OutputDir = $OutputDir
    }
    return
  }

  "dir-capture-v2" {
    if(-not $InputDir){ Die "MISSING: InputDir" }
    if(-not $OutputManifest){ Die "MISSING: OutputManifest" }

    Run (Join-Path $Scripts "triad_capture_v2.ps1") @{
      RepoRoot = $RepoRoot
      InputDir = $InputDir
      OutputManifest = $OutputManifest
    }
    return
  }

  "dir-verify" {
    if(-not $BaseManifest){ Die "MISSING: BaseManifest" }
    if(-not $CompareManifest){ Die "MISSING: CompareManifest" }

    Run (Join-Path $Scripts "triad_verify_v1.ps1") @{
      RepoRoot = $RepoRoot
      BaseManifest = $BaseManifest
      CompareManifest = $CompareManifest
    }
    return
  }

  "archive-reset" {
    if(-not $ArchiveDir){ Die "MISSING: ArchiveDir" }

    if(Test-Path -LiteralPath $ArchiveDir){
      Get-ChildItem -LiteralPath $ArchiveDir -Force | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
      }
    }

    Write-Host ("ARCHIVE_RESET_OK: " + $ArchiveDir)
    return
  }

  "archive-pack" {
    if(-not $InputDir){ Die "MISSING: InputDir" }
    if(-not $ArchiveDir){ Die "MISSING: ArchiveDir" }

    Run (Join-Path $Scripts "triad_archive_pack_v1.ps1") @{
      RepoRoot = $RepoRoot
      InputDir = $InputDir
      ArchiveDir = $ArchiveDir
    }
    return
  }

  "archive-verify" {
    if(-not $ArchiveDir){ Die "MISSING: ArchiveDir" }

    Run (Join-Path $Scripts "triad_archive_verify_v1.ps1") @{
      RepoRoot = $RepoRoot
      ArchiveDir = $ArchiveDir
    }
    return
  }

  "archive-extract" {
    if(-not $ArchiveDir){ Die "MISSING: ArchiveDir" }
    if(-not $OutputDir){ Die "MISSING: OutputDir" }

    Run (Join-Path $Scripts "triad_archive_extract_v1.ps1") @{
      RepoRoot = $RepoRoot
      ArchiveDir = $ArchiveDir
      OutputDir = $OutputDir
    }
    return
  }

  "transform-reset" {
    if(-not $OutputPath){ Die "MISSING: OutputPath" }

    if(Test-Path -LiteralPath $OutputPath){
      Remove-Item -LiteralPath $OutputPath -Force
    }

    if($ManifestPath -and (Test-Path -LiteralPath $ManifestPath)){
      Remove-Item -LiteralPath $ManifestPath -Force
    }

    Write-Host "TRANSFORM_RESET_OK"
    return
  }

  "transform-apply" {
    if(-not $InputPath){ Die "MISSING: InputPath" }
    if(-not $OutputPath){ Die "MISSING: OutputPath" }
    if(-not $TransformType){ Die "MISSING: TransformType" }

    Run (Join-Path $Scripts "triad_transform_apply_v1.ps1") @{
      RepoRoot = $RepoRoot
      TransformType = $TransformType
      InputPath = $InputPath
      OutputPath = $OutputPath
    }
    return
  }

  "transform-verify" {
    if(-not $ManifestPath){ Die "MISSING: ManifestPath" }

    Run (Join-Path $Scripts "triad_transform_verify_v1.ps1") @{
      RepoRoot = $RepoRoot
      ManifestPath = $ManifestPath
    }
    return
  }

  default {
    Die ("UNKNOWN_COMMAND: " + $Command)
  }
}
