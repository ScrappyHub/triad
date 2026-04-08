param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Ensure-Dir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ throw "ENSURE_DIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
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

function Read-Utf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  return (Get-Content -Raw -LiteralPath $Path -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Capture = Join-Path $RepoRoot "scripts\triad_capture_tree_v1.ps1"
$Prepare = Join-Path $RepoRoot "scripts\triad_restore_prepare_v1.ps1"
$Verify  = Join-Path $RepoRoot "scripts\triad_restore_verify_v1.ps1"
$Commit  = Join-Path $RepoRoot "scripts\triad_restore_commit_v1.ps1"

foreach($p in @($Capture,$Prepare,$Verify,$Commit)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $p) }
}

$WorkRoot = Join-Path $RepoRoot "scripts\_work\stress_deeper_tree_v1"
if(Test-Path -LiteralPath $WorkRoot -PathType Container){
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
Ensure-Dir $WorkRoot

$InputRoot      = Join-Path $WorkRoot "input"
$CaptureOutDir  = Join-Path $WorkRoot "capture_out"
$RestoreOutFile = Join-Path $WorkRoot "restored.bin"

Ensure-Dir $InputRoot
Ensure-Dir $CaptureOutDir
Ensure-Dir (Join-Path $InputRoot "level1")
Ensure-Dir (Join-Path $InputRoot "level1\level2")
Ensure-Dir (Join-Path $InputRoot "level1\level2\level3")

Write-Utf8NoBomLf (Join-Path $InputRoot "root_note.txt") "root file for deeper tree stress"
Write-Utf8NoBomLf (Join-Path $InputRoot "level1\alpha.txt") "alpha"
Write-Utf8NoBomLf (Join-Path $InputRoot "level1\level2\beta.txt") "beta"
Write-Utf8NoBomLf (Join-Path $InputRoot "level1\level2\level3\gamma.txt") "gamma"

$payloadPath = Join-Path $InputRoot "payload.bin"
$bytes = New-Object byte[] 1572865
for($i = 0; $i -lt $bytes.Length; $i++){
  $bytes[$i] = [byte]($i % 251)
}
[System.IO.File]::WriteAllBytes($payloadPath,$bytes)

& $Capture -RepoRoot $RepoRoot -InputDir $InputRoot -OutDir $CaptureOutDir | Out-Host

$SnapshotDir = $CaptureOutDir
if(-not (Test-Path -LiteralPath $SnapshotDir -PathType Container)){ Die ("CAPTURE_OUTPUT_MISSING: " + $SnapshotDir) }

$TreeManifest = Join-Path $SnapshotDir "snapshot.tree.manifest.json"
if(-not (Test-Path -LiteralPath $TreeManifest -PathType Leaf)){ Die ("CAPTURE_TREE_MANIFEST_MISSING: " + $TreeManifest) }

& $Prepare -RepoRoot $RepoRoot -SnapshotDir $SnapshotDir -OutFile $RestoreOutFile | Out-Host

$planPath = Get-ChildItem -LiteralPath $WorkRoot -Recurse -File |
  Where-Object { $_.Name -like "*.triad_plan_v1_*.json" } |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1

if($null -eq $planPath){ Die "PREPARE_PLAN_NOT_FOUND" }
$planPath = $planPath.FullName
if(-not (Test-Path -LiteralPath $planPath -PathType Leaf)){ Die ("PREPARE_PLAN_MISSING: " + $planPath) }

& $Verify -RepoRoot $RepoRoot -PlanPath $planPath | Out-Host
& $Commit -RepoRoot $RepoRoot -PlanPath $planPath | Out-Host

$manifestPath = Join-Path $SnapshotDir "snapshot.tree.manifest.json"
if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){ Die ("MISSING_MANIFEST: " + $manifestPath) }
$manifestObj = Read-Utf8 $manifestPath | ConvertFrom-Json
$payloadEntry = $null
foreach($e in @(@($manifestObj.entries))){
  if($null -eq $e){ continue }
  $type = ""
  $path = ""
  try { $type = [string]$e.type } catch { $type = "" }
  try { $path = [string]$e.path } catch { $path = "" }
  if($type -eq "file" -and $path -eq "payload.bin"){
    $payloadEntry = $e
    break
  }
}
if($null -eq $payloadEntry){ Die "DEEPER_TREE_PAYLOAD_ENTRY_NOT_FOUND" }

Write-Host ("STRESS_WORKDIR: " + $WorkRoot) -ForegroundColor DarkGray
Write-Host ("STRESS_SNAPSHOT_ID: " + [string]$manifestObj.snapshot_id) -ForegroundColor Cyan
Write-Host ("STRESS_PAYLOAD_SHA: " + [string]$payloadEntry.sha256) -ForegroundColor DarkGray
Write-Host ("STRESS_PAYLOAD_LEN: " + [string]$payloadEntry.length) -ForegroundColor DarkGray
Write-Host "TRIAD_RESTORE_STRESS_DEEPER_TREE_V1_OK" -ForegroundColor Green
