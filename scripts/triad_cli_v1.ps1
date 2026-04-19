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

function Run($Script,$Params){
  if(-not (Test-Path $Script -PathType Leaf)){
    throw ("SCRIPT_NOT_FOUND: " + $Script)
  }
  & $Script @Params
}

$RepoRoot = (Resolve-Path $RepoRoot).Path
$Scripts = Join-Path $RepoRoot "scripts"

switch($Command){

  "verify-release" {
    Run (Join-Path $Scripts "_RUN_triad_full_green_v1.ps1") @{
      RepoRoot = $RepoRoot
    }
    return
  }

  "dir-full-green" {
    Run (Join-Path $Scripts "_RUN_triad_dir_full_green_v1.ps1") @{
      RepoRoot = $RepoRoot
      InputDir = $(if($InputDir){ $InputDir } else { ".\scripts\_work\triad_archive_selftest_v1\input" })
    }
    return
  }

  "dir-blockmap" {
    if(-not $InputDir){ throw "MISSING: InputDir" }
    if(-not $OutputManifest){ throw "MISSING: OutputManifest" }

    Run (Join-Path $Scripts "triad_blockmap_dir_v1.ps1") @{
      RepoRoot = $RepoRoot
      InputDir = $InputDir
      OutputManifest = $OutputManifest
      BlockSize = $BlockSize
    }
    return
  }

  "dir-store-export" {
    if(-not $InputDir){ throw "MISSING: InputDir" }
    if(-not $BlockmapManifest){ throw "MISSING: BlockmapManifest" }
    if(-not $OutputDir){ throw "MISSING: OutputDir" }

    Run (Join-Path $Scripts "triad_block_store_export_v1.ps1") @{
      RepoRoot = $RepoRoot
      InputDir = $InputDir
      BlockmapManifest = $BlockmapManifest
      OutputStoreDir = $OutputDir
    }
    return
  }

  "dir-restore" {
    if(-not $StoreDir){ throw "MISSING: StoreDir" }
    if(-not $OutputDir){ throw "MISSING: OutputDir" }

    Run (Join-Path $Scripts "triad_restore_dir_from_block_store_v1.ps1") @{
      RepoRoot = $RepoRoot
      StoreDir = $StoreDir
      OutputDir = $OutputDir
    }
    return
  }

  "dir-capture-v2" {
    if(-not $InputDir){ throw "MISSING: InputDir" }
    if(-not $OutputManifest){ throw "MISSING: OutputManifest" }

    Run (Join-Path $Scripts "triad_capture_v2.ps1") @{
      RepoRoot = $RepoRoot
      InputDir = $InputDir
      OutputManifest = $OutputManifest
    }
    return
  }

  "dir-verify" {
    if(-not $BaseManifest){ throw "MISSING: BaseManifest" }
    if(-not $CompareManifest){ throw "MISSING: CompareManifest" }

    Run (Join-Path $Scripts "triad_verify_v1.ps1") @{
      RepoRoot = $RepoRoot
      BaseManifest = $BaseManifest
      CompareManifest = $CompareManifest
    }
    return
  }

  "archive-reset" {
    if(-not $ArchiveDir){ throw "MISSING: ArchiveDir" }

    if(Test-Path $ArchiveDir){
      Get-ChildItem $ArchiveDir -Force | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force
      }
    }

    Write-Host ("ARCHIVE_RESET_OK: " + $ArchiveDir)
    return
  }

  "archive-pack" {
    if(-not $InputDir){ throw "MISSING: InputDir" }
    if(-not $ArchiveDir){ throw "MISSING: ArchiveDir" }

    Run (Join-Path $Scripts "triad_archive_pack_v1.ps1") @{
      RepoRoot = $RepoRoot
      InputDir = $InputDir
      ArchiveDir = $ArchiveDir
    }
    return
  }

  "archive-verify" {
    if(-not $ArchiveDir){ throw "MISSING: ArchiveDir" }

    Run (Join-Path $Scripts "triad_archive_verify_v1.ps1") @{
      RepoRoot = $RepoRoot
      ArchiveDir = $ArchiveDir
    }
    return
  }

  "archive-extract" {
    if(-not $ArchiveDir){ throw "MISSING: ArchiveDir" }
    if(-not $OutputDir){ throw "MISSING: OutputDir" }

    Run (Join-Path $Scripts "triad_archive_extract_v1.ps1") @{
      RepoRoot = $RepoRoot
      ArchiveDir = $ArchiveDir
      OutputDir = $OutputDir
    }
    return
  }

  "transform-reset" {
    if(-not $OutputPath){ throw "MISSING: OutputPath" }

    if(Test-Path $OutputPath){
      Remove-Item $OutputPath -Force
    }

    if($ManifestPath -and (Test-Path $ManifestPath)){
      Remove-Item $ManifestPath -Force
    }

    Write-Host ("TRANSFORM_RESET_OK")
    return
  }

  "transform-apply" {
    if(-not $InputPath){ throw "MISSING: InputPath" }
    if(-not $OutputPath){ throw "MISSING: OutputPath" }
    if(-not $TransformType){ throw "MISSING: TransformType" }

    Run (Join-Path $Scripts "triad_transform_apply_v1.ps1") @{
      RepoRoot = $RepoRoot
      TransformType = $TransformType
      InputPath = $InputPath
      OutputPath = $OutputPath
    }
    return
  }

  "transform-verify" {
    if(-not $ManifestPath){ throw "MISSING: ManifestPath" }

    Run (Join-Path $Scripts "triad_transform_verify_v1.ps1") @{
      RepoRoot = $RepoRoot
      ManifestPath = $ManifestPath
    }
    return
  }

  default {
    throw ("UNKNOWN_COMMAND: " + $Command)
  }
}
