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
    try { $hash = $sha.ComputeHash($fs) } finally { $fs.Dispose() }
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

$WorkRoot = Join-Path $RepoRoot "scripts\_work\stress_repeated_blocks_v1"
if(Test-Path -LiteralPath $WorkRoot -PathType Container){
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
Ensure-Dir $WorkRoot
$InputRoot      = Join-Path $WorkRoot "input"
$CaptureOutDir  = Join-Path $WorkRoot "capture_out"
$RestoreOutFile = Join-Path $WorkRoot "restored.bin"
Ensure-Dir $InputRoot
Ensure-Dir $CaptureOutDir

$chunk = 1048576
$a = New-Object byte[] $chunk
for($i=0; $i -lt $a.Length; $i++){ $a[$i] = [byte](($i * 7) % 251) }
$b = New-Object byte[] $chunk
for($i=0; $i -lt $b.Length; $i++){ $b[$i] = [byte](($i * 13 + 19) % 251) }
$tail = New-Object byte[] 524288
for($i=0; $i -lt $tail.Length; $i++){ $tail[$i] = [byte](($i * 5 + 3) % 251) }
$fs = [System.IO.File]::Open((Join-Path $InputRoot "payload.bin"),[System.IO.FileMode]::Create,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)
try {
  $fs.Write($a,0,$a.Length)
  $fs.Write($a,0,$a.Length)
  $fs.Write($a,0,$a.Length)
  $fs.Write($b,0,$b.Length)
  $fs.Write($tail,0,$tail.Length)
} finally {
  $fs.Dispose()
}
Write-Utf8NoBomLf (Join-Path $InputRoot "notes.txt") "repeated block stress"

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
$PayloadEntry = $null
foreach($e in $Entries){
  if($null -eq $e){ continue }
  $type = ""
  $path = ""
  try { $type = [string]$e.type } catch { $type = "" }
  try { $path = [string]$e.path } catch { $path = "" }
  if($type -eq "file" -and $path -eq "payload.bin"){ $PayloadEntry = $e; break }
}
if($null -eq $PayloadEntry){ Die "REPEATED_BLOCK_PAYLOAD_ENTRY_NOT_FOUND" }
$Blocks = @(@($PayloadEntry.blocks))
if($Blocks.Count -lt 5){ Die ("REPEATED_BLOCK_BLOCKCOUNT_TOO_LOW: " + $Blocks.Count) }
$Seen = @{}
$RepeatedCount = 0
foreach($b in $Blocks){
  $sha = ""
  try { $sha = [string]$b.sha256 } catch { $sha = "" }
  if([string]::IsNullOrWhiteSpace($sha)){ continue }
  if($Seen.ContainsKey($sha)){
    $Seen[$sha] = [int]$Seen[$sha] + 1
  } else {
    $Seen[$sha] = 1
  }
}
foreach($k in $Seen.Keys){
  if([int]$Seen[$k] -gt 1){ $RepeatedCount++ }
}
if($RepeatedCount -lt 1){ Die "REPEATED_BLOCK_REUSE_NOT_OBSERVED" }
$RestoredSha = Sha256HexFile $RestoreOutFile
$ExpectedSha = [string]$PayloadEntry.sha256
if($RestoredSha -ne $ExpectedSha){ Die ("RESTORED_SHA_MISMATCH: got=" + $RestoredSha + " expected=" + $ExpectedSha) }
Write-Host ("STRESS_WORKDIR: " + $WorkRoot) -ForegroundColor DarkGray
Write-Host ("STRESS_SNAPSHOT_ID: " + [string]$ManifestObj.snapshot_id) -ForegroundColor Cyan
Write-Host ("BLOCK_COUNT: " + $Blocks.Count) -ForegroundColor DarkGray
Write-Host ("REPEATED_SHA_GROUPS: " + $RepeatedCount) -ForegroundColor DarkGray
Write-Host ("RESTORED_SHA: " + $RestoredSha) -ForegroundColor DarkGray
Write-Host "TRIAD_RESTORE_STRESS_REPEATED_BLOCKS_V1_OK" -ForegroundColor Green
