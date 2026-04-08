param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$Message){ throw $Message }

function Read-Utf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  return (Get-Content -Raw -LiteralPath $Path -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$NegRoot    = Join-Path $RepoRoot "test_vectors\restore\v1\negative\block_sha_corruption_invalid_v1"
$PlansDir   = Join-Path $NegRoot "plans"
$VerifyPath = Join-Path $RepoRoot "scripts\triad_restore_verify_v1.ps1"

if(-not (Test-Path -LiteralPath $NegRoot -PathType Container)){ Die "NEG_VECTOR_NOT_FOUND" }
if(-not (Test-Path -LiteralPath $PlansDir -PathType Container)){ Die "NEG_PLANS_DIR_NOT_FOUND" }
if(-not (Test-Path -LiteralPath $VerifyPath -PathType Leaf)){ Die "VERIFY_SCRIPT_NOT_FOUND" }

$Plan = Get-ChildItem -LiteralPath $PlansDir -File |
  Where-Object { $_.Name -like "*.triad_plan_v1_*.json" } |
  Sort-Object Name |
  Select-Object -First 1

if($null -eq $Plan){ Die "MISSING_NEG_PLAN" }
$PlanPath = $Plan.FullName
$PlanObj  = Read-Utf8 $PlanPath | ConvertFrom-Json

$ManifestPath = [string]$PlanObj.manifest_path
$SnapshotDir  = [string]$PlanObj.snapshot_dir
$TmpPath      = [string]$PlanObj.tmp_file

if([string]::IsNullOrWhiteSpace($ManifestPath)){ Die "NEG_PLAN_MANIFEST_PATH_EMPTY" }
if([string]::IsNullOrWhiteSpace($SnapshotDir)){ Die "NEG_PLAN_SNAPSHOT_DIR_EMPTY" }
if([string]::IsNullOrWhiteSpace($TmpPath)){ Die "NEG_PLAN_TMP_FILE_EMPTY" }

if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){ Die ("NEG_MANIFEST_NOT_FOUND: " + $ManifestPath) }
if(-not (Test-Path -LiteralPath $SnapshotDir -PathType Container)){ Die ("NEG_SNAPSHOT_DIR_NOT_FOUND: " + $SnapshotDir) }

$TmpDir = Split-Path -Parent $TmpPath
if($TmpDir -and -not (Test-Path -LiteralPath $TmpDir -PathType Container)){
  New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null
}
if(-not (Test-Path -LiteralPath $TmpPath -PathType Leaf)){
  $fs0 = [System.IO.File]::Open($TmpPath,[System.IO.FileMode]::Create,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)
  $fs0.Dispose()
}

$ManifestObj = Read-Utf8 $ManifestPath | ConvertFrom-Json
$Entries = @(@($ManifestObj.entries))
$PayloadEntry = $null
foreach($e in $Entries){
  if($null -eq $e){ continue }
  $type = ""
  $path = ""
  try { $type = [string]$e.type } catch { $type = "" }
  try { $path = [string]$e.path } catch { $path = "" }
  if($type -eq "file" -and $path -eq "payload.bin"){
    $PayloadEntry = $e
    break
  }
}
if($null -eq $PayloadEntry){ Die "NEG_PAYLOAD_ENTRY_NOT_FOUND" }

$Blocks = @(@($PayloadEntry.blocks))
if($Blocks.Count -lt 1){ Die "NEG_PAYLOAD_BLOCKS_EMPTY" }
$FirstBlock = $Blocks[0]
$FirstRel = [string]$FirstBlock.path
if([string]::IsNullOrWhiteSpace($FirstRel)){ Die "NEG_FIRST_BLOCK_PATH_EMPTY" }
$FirstBlockPath = Join-Path $SnapshotDir ($FirstRel -replace "/","\")
if(-not (Test-Path -LiteralPath $FirstBlockPath -PathType Leaf)){ Die ("NEG_FIRST_BLOCK_NOT_FOUND: " + $FirstBlockPath) }

$OriginalBytes = [System.IO.File]::ReadAllBytes($FirstBlockPath)
if($OriginalBytes.Length -lt 1){ Die "NEG_FIRST_BLOCK_EMPTY" }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"
$psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$VerifyPath`" -RepoRoot `"$RepoRoot`" -PlanPath `"$PlanPath`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

try {
  $CorruptBytes = New-Object byte[] $OriginalBytes.Length
  [Array]::Copy($OriginalBytes,$CorruptBytes,$OriginalBytes.Length)
  $CorruptBytes[0] = $CorruptBytes[0] -bxor 1
  [System.IO.File]::WriteAllBytes($FirstBlockPath,$CorruptBytes)

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  [void]$p.Start()
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  $out = $stdout + "`n" + $stderr

  if($p.ExitCode -eq 0){
    Die "NEGATIVE_TEST_FAILED_SHOULD_NOT_PASS"
  }

  if($out -notmatch "BLOCK_HASH_MISMATCH"){
    Die ("EXPECTED_FAILURE_TOKEN_NOT_FOUND: " + $out)
  }

  Write-Host ("NEG_PLAN: " + $PlanPath) -ForegroundColor DarkGray
  Write-Host ("NEG_BLOCK: " + $FirstBlockPath) -ForegroundColor DarkGray
  Write-Host "TRIAD_NEGATIVE_VECTOR_BLOCK_SHA_CORRUPTION_V1_SELFTEST_OK" -ForegroundColor Green
}
finally {
  [System.IO.File]::WriteAllBytes($FirstBlockPath,$OriginalBytes)
}
