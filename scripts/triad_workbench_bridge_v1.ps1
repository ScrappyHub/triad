param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Action,
  [Parameter(Mandatory=$false)][string]$InputPath,
  [Parameter(Mandatory=$false)][string]$OutputPath,
  [Parameter(Mandatory=$false)][string]$ArchiveDir,
  [Parameter(Mandatory=$false)][string]$TransformType,
  [Parameter(Mandatory=$false)][string]$ManifestPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Emit-Json([object]$Obj){
  $json = $Obj | ConvertTo-Json -Depth 100 -Compress
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
  Write-Output $json
}

function Ensure-Dir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ throw "ENSURE_DIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Reset-Dir([string]$Path){
  if(Test-Path -LiteralPath $Path -PathType Container){
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
      Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
  } else {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ Ensure-Dir $dir }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Normalize-UiPath([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return $Path }
  $p = $Path.Trim()
  while($p.Contains("\\\\")){ $p = $p.Replace("\\\\","\") }
  return $p
}

function Ensure-TransformDemoFiles([string]$InputPath,[string]$OutputPath,[string]$ManifestPath){
  $input = Normalize-UiPath $InputPath
  $output = Normalize-UiPath $OutputPath
  $manifest = Normalize-UiPath $ManifestPath

  $demoRoot = Split-Path -Parent $input
  if($demoRoot){ Ensure-Dir $demoRoot }

  if(-not (Test-Path -LiteralPath $input -PathType Leaf)){
    Write-Utf8NoBomLf $input " alpha   `r`n beta`t`t`r`n gamma   "
  }

  $outDir = Split-Path -Parent $output
  if($outDir){ Ensure-Dir $outDir }

  $manifestDir = Split-Path -Parent $manifest
  if($manifestDir){ Ensure-Dir $manifestDir }

  return [pscustomobject]@{
    input = $input
    output = $output
    manifest = $manifest
  }
}

function Invoke-TriadScript {
  param(
    [Parameter(Mandatory=$true)][string]$ScriptPath,
    [Parameter(Mandatory=$true)][hashtable]$Params,
    [Parameter(Mandatory=$true)][string]$ActionName
  )

  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){
    return [pscustomobject]@{
      ok = $false
      action = $ActionName
      exit_code = 1
      stdout = ""
      stderr = ("SCRIPT_NOT_FOUND: " + $ScriptPath)
    }
  }

  try {
    $all = & $ScriptPath @Params 2>&1 | Out-String
    return [pscustomobject]@{
      ok = $true
      action = $ActionName
      exit_code = 0
      stdout = $all
      stderr = ""
    }
  }
  catch {
    $msg = $_ | Out-String
    return [pscustomobject]@{
      ok = $false
      action = $ActionName
      exit_code = 1
      stdout = ""
      stderr = $msg
    }
  }
}

function Refresh-WorkbenchExport([string]$RepoRoot){
  $script = Join-Path $RepoRoot "scripts\triad_workbench_export_v1.ps1"
  if(Test-Path -LiteralPath $script -PathType Leaf){
    try {
      & $script -RepoRoot $RepoRoot | Out-Null
      $src = Join-Path $RepoRoot "workbench\triad.workbench.export.v1.json"
      $dstDir = Join-Path $RepoRoot "workbench\public"
      $dst = Join-Path $dstDir "triad.workbench.export.v1.json"
      Ensure-Dir $dstDir
      if(Test-Path -LiteralPath $src -PathType Leaf){
        Copy-Item -LiteralPath $src -Destination $dst -Force
      }
    } catch {}
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$WorkbenchDemoRoot = Join-Path $RepoRoot "workbench\demo"
$ArchiveDemoInput = Join-Path $WorkbenchDemoRoot "archive_input"
$ArchiveDemoOut = Join-Path $WorkbenchDemoRoot "archive_out"
$ArchiveDemoExtract = Join-Path $WorkbenchDemoRoot "archive_extract"
$TransformDemoInput = Join-Path $WorkbenchDemoRoot "transform_input.txt"
$TransformDemoOutput = Join-Path $WorkbenchDemoRoot "transform_output.txt"
$TransformDemoManifest = Join-Path $WorkbenchDemoRoot "transform_output.txt.transform_manifest.json"

$InputPath = Normalize-UiPath $InputPath
$OutputPath = Normalize-UiPath $OutputPath
$ArchiveDir = Normalize-UiPath $ArchiveDir
$ManifestPath = Normalize-UiPath $ManifestPath

switch($Action){
  "run_verified_release" {
    $script = Join-Path $ScriptsDir "_RUN_triad_full_green_v1.ps1"
    $r = Invoke-TriadScript -ScriptPath $script -Params @{ RepoRoot = $RepoRoot } -ActionName $Action
    if($r.ok){ Refresh-WorkbenchExport $RepoRoot }
    Emit-Json $r
    exit 0
  }

  "archive_reset_demo" {
    Ensure-Dir $WorkbenchDemoRoot
    Reset-Dir $ArchiveDemoInput
    Reset-Dir $ArchiveDemoOut
    Reset-Dir $ArchiveDemoExtract
    Write-Utf8NoBomLf (Join-Path $ArchiveDemoInput "a.txt") "alpha"
    Write-Utf8NoBomLf (Join-Path $ArchiveDemoInput "b.txt") "beta"
    Emit-Json ([pscustomobject]@{
      ok = $true
      action = $Action
      exit_code = 0
      stdout = ("ARCHIVE_DEMO_READY`nINPUT=" + $ArchiveDemoInput + "`nARCHIVE=" + $ArchiveDemoOut + "`nEXTRACT=" + $ArchiveDemoExtract)
      stderr = ""
      archive_input = $ArchiveDemoInput
      archive_dir = $ArchiveDemoOut
      extract_dir = $ArchiveDemoExtract
    })
    exit 0
  }

  "transform_reset_demo" {
    Ensure-Dir $WorkbenchDemoRoot
    if(Test-Path -LiteralPath $TransformDemoOutput -PathType Leaf){ Remove-Item -LiteralPath $TransformDemoOutput -Force }
    if(Test-Path -LiteralPath $TransformDemoManifest -PathType Leaf){ Remove-Item -LiteralPath $TransformDemoManifest -Force }
    Write-Utf8NoBomLf $TransformDemoInput " alpha   `r`n beta`t`t`r`n gamma   "
    Emit-Json ([pscustomobject]@{
      ok = $true
      action = $Action
      exit_code = 0
      stdout = ("TRANSFORM_DEMO_READY`nINPUT=" + $TransformDemoInput + "`nOUTPUT=" + $TransformDemoOutput + "`nMANIFEST=" + $TransformDemoManifest)
      stderr = ""
      input_path = $TransformDemoInput
      output_path = $TransformDemoOutput
      manifest_path = $TransformDemoManifest
    })
    exit 0
  }

  "archive_pack" {
    if([string]::IsNullOrWhiteSpace($InputPath)){ $InputPath = $ArchiveDemoInput }
    if([string]::IsNullOrWhiteSpace($ArchiveDir)){ $ArchiveDir = $ArchiveDemoOut }
    $script = Join-Path $ScriptsDir "triad_archive_pack_v1.ps1"
    $r = Invoke-TriadScript -ScriptPath $script -Params @{
      RepoRoot = $RepoRoot
      InputDir = $InputPath
      ArchiveDir = $ArchiveDir
    } -ActionName $Action
    if($r.ok){ Refresh-WorkbenchExport $RepoRoot }
    Emit-Json $r
    exit 0
  }

  "archive_verify" {
    if([string]::IsNullOrWhiteSpace($ArchiveDir)){ $ArchiveDir = $ArchiveDemoOut }
    $script = Join-Path $ScriptsDir "triad_archive_verify_v1.ps1"
    $r = Invoke-TriadScript -ScriptPath $script -Params @{
      RepoRoot = $RepoRoot
      ArchiveDir = $ArchiveDir
    } -ActionName $Action
    Emit-Json $r
    exit 0
  }

  "archive_extract" {
    if([string]::IsNullOrWhiteSpace($ArchiveDir)){ $ArchiveDir = $ArchiveDemoOut }
    if([string]::IsNullOrWhiteSpace($OutputPath)){ $OutputPath = $ArchiveDemoExtract }
    $script = Join-Path $ScriptsDir "triad_archive_extract_v1.ps1"
    $r = Invoke-TriadScript -ScriptPath $script -Params @{
      RepoRoot = $RepoRoot
      ArchiveDir = $ArchiveDir
      OutputDir = $OutputPath
    } -ActionName $Action
    Emit-Json $r
    exit 0
  }

  "transform_apply" {
    if([string]::IsNullOrWhiteSpace($InputPath)){ $InputPath = $TransformDemoInput }
    if([string]::IsNullOrWhiteSpace($OutputPath)){ $OutputPath = $TransformDemoOutput }
    if([string]::IsNullOrWhiteSpace($ManifestPath)){ $ManifestPath = $TransformDemoManifest }
    $demo = Ensure-TransformDemoFiles -InputPath $InputPath -OutputPath $OutputPath -ManifestPath $ManifestPath
    $script = Join-Path $ScriptsDir "triad_transform_apply_v1.ps1"
    $r = Invoke-TriadScript -ScriptPath $script -Params @{
      RepoRoot = $RepoRoot
      TransformType = $TransformType
      InputPath = $demo.input
      OutputPath = $demo.output
    } -ActionName $Action
    Emit-Json $r
    exit 0
  }

  "transform_verify" {
    if([string]::IsNullOrWhiteSpace($ManifestPath)){ $ManifestPath = $TransformDemoManifest }
    $script = Join-Path $ScriptsDir "triad_transform_verify_v1.ps1"
    $r = Invoke-TriadScript -ScriptPath $script -Params @{
      RepoRoot = $RepoRoot
      ManifestPath = $ManifestPath
    } -ActionName $Action
    Emit-Json $r
    exit 0
  }

  default {
    Emit-Json ([pscustomobject]@{
      ok = $false
      action = $Action
      exit_code = 1
      stdout = ""
      stderr = ("UNKNOWN_ACTION: " + $Action)
    })
    exit 0
  }
}
