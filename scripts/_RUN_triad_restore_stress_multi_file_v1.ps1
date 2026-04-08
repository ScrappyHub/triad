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

function Sha256HexFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [System.IO.File]::OpenRead($Path)
    try {
      $hash = $sha.ComputeHash($fs)
    } finally {
      $fs.Dispose()
    }
  } finally {
    $sha.Dispose()
  }
  return ([BitConverter]::ToString($hash)).Replace("-","").ToLowerInvariant()
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Capture = Join-Path $RepoRoot "scripts\triad_capture_tree_v1.ps1"
$Prepare = Join-Path $RepoRoot "scripts\triad_restore_prepare_v1.ps1"
$Verify  = Join-Path $RepoRoot "scripts\triad_restore_verify_v1.ps1"
$Commit  = Join-Path $RepoRoot "scripts\triad_restore_commit_v1.ps1"

foreach($p in @($Capture,$Prepare,$Verify,$Commit)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $p) }
}

$WorkRoot = Join-Path $RepoRoot "scripts\_work\stress_multi_file_v1"
if(Test-Path -LiteralPath $WorkRoot -PathType Container){
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
Ensure-Dir $WorkRoot
$InputRoot      = Join-Path $WorkRoot "input"
$CaptureOutDir  = Join-Path $WorkRoot "capture_out"
$RestoreOutFile = Join-Path $WorkRoot "restored_payload_a.bin"
Ensure-Dir $InputRoot
Ensure-Dir $CaptureOutDir
Ensure-Dir (Join-Path $InputRoot "nested")
Ensure-Dir (Join-Path $InputRoot "nested\inner")

$bytesA = New-Object byte[] 1048576
for($i=0; $i -lt $bytesA.Length; $i++){ $bytesA[$i] = [byte]($i % 251) }
$bytesB = New-Object byte[] 1048576
for($i=0; $i -lt $bytesB.Length; $i++){ $bytesB[$i] = [byte](($i + 17) % 251) }
$bytesC = New-Object byte[] 524288
for($i=0; $i -lt $bytesC.Length; $i++){ $bytesC[$i] = [byte](($i + 33) % 251) }
[System.IO.File]::WriteAllBytes((Join-Path $InputRoot "payload_a.bin"),$bytesA)
[System.IO.File]::WriteAllBytes((Join-Path $InputRoot "nested\payload_b.bin"),$bytesB)
[System.IO.File]::WriteAllBytes((Join-Path $InputRoot "nested\inner\payload_c.bin"),$bytesC)
Write-Utf8NoBomLf (Join-Path $InputRoot "readme.txt") "multi file stress"

& $Capture -RepoRoot $RepoRoot -InputDir $InputRoot -OutDir $CaptureOutDir | Out-Host
$SnapshotDir = $CaptureOutDir
if(-not (Test-Path -LiteralPath $SnapshotDir -PathType Container)){ Die ("CAPTURE_OUTPUT_MISSING: " + $SnapshotDir) }
$TreeManifest = Join-Path $SnapshotDir "snapshot.tree.manifest.json"
if(-not (Test-Path -LiteralPath $TreeManifest -PathType Leaf)){ Die ("CAPTURE_TREE_MANIFEST_MISSING: " + $TreeManifest) }

& $Prepare -RepoRoot $RepoRoot -SnapshotDir $SnapshotDir -OutFile $RestoreOutFile | Out-Host
$PlanPath = Get-ChildItem -LiteralPath $WorkRoot -Recurse -File |
  Where-Object { $_.Name -like "*.triad_plan_v1_*.json" } |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1
if($null -eq $PlanPath){ Die "PREPARE_PLAN_NOT_FOUND" }
$PlanPath = $PlanPath.FullName

& $Verify -RepoRoot $RepoRoot -PlanPath $PlanPath | Out-Host
& $Commit -RepoRoot $RepoRoot -PlanPath $PlanPath | Out-Host

$ManifestObj = Read-Utf8 $TreeManifest | ConvertFrom-Json
$Entries = @(@($ManifestObj.entries))
$FileEntries = @()
foreach($e in $Entries){
  if($null -eq $e){ continue }
  $type = ""
  try { $type = [string]$e.type } catch { $type = "" }
  if($type -eq "file"){ $FileEntries += $e }
}
if($FileEntries.Count -lt 3){ Die ("MULTI_FILE_ENTRY_COUNT_TOO_LOW: " + $FileEntries.Count) }

$NeedPaths = @("payload_a.bin","nested/payload_b.bin","nested/inner/payload_c.bin")
foreach($need in $NeedPaths){
  $found = $false
  foreach($e in $FileEntries){
    $p = ""
    try { $p = [string]$e.path } catch { $p = "" }
    if($p -eq $need){ $found = $true; break }
  }
  if(-not $found){ Die ("MULTI_FILE_PATH_NOT_FOUND: " + $need) }
}

$PayloadAPath = Join-Path $InputRoot "payload_a.bin"
$PayloadBPath = Join-Path $InputRoot "nested\payload_b.bin"
$PayloadCPath = Join-Path $InputRoot "nested\inner\payload_c.bin"
$ShaA = Sha256HexFile $PayloadAPath
$ShaB = Sha256HexFile $PayloadBPath
$ShaC = Sha256HexFile $PayloadCPath

Write-Host ("STRESS_WORKDIR: " + $WorkRoot) -ForegroundColor DarkGray
Write-Host ("STRESS_SNAPSHOT_ID: " + [string]$ManifestObj.snapshot_id) -ForegroundColor Cyan
Write-Host ("MULTI_FILE_COUNT: " + $FileEntries.Count) -ForegroundColor DarkGray
Write-Host ("SHA_A: " + $ShaA) -ForegroundColor DarkGray
Write-Host ("SHA_B: " + $ShaB) -ForegroundColor DarkGray
Write-Host ("SHA_C: " + $ShaC) -ForegroundColor DarkGray
Write-Host "TRIAD_RESTORE_STRESS_MULTI_FILE_V1_OK" -ForegroundColor Green
