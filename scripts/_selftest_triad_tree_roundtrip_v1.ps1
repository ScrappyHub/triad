param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function ParseGate([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }
  [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Path -Encoding UTF8)) | Out-Null
}

function Sha256HexFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die ("MISSING_REPO: " + $RepoRoot) }

$ScriptsDir = Join-Path $RepoRoot "scripts"
$Capture    = Join-Path $ScriptsDir "triad_capture_tree_v1.ps1"
$Prep       = Join-Path $ScriptsDir "triad_restore_tree_prepare_v1.ps1"
$Verify     = Join-Path $ScriptsDir "triad_restore_tree_verify_v1.ps1"
$Commit     = Join-Path $ScriptsDir "triad_restore_tree_commit_v1.ps1"

foreach($p in @($Capture,$Prep,$Verify,$Commit)){
  ParseGate $p
}

# work dir
$WorkRoot = Join-Path $ScriptsDir "_work"
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
$RunId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss") + "_" + ([Guid]::NewGuid().ToString("N"))
$Work  = Join-Path $WorkRoot ("tree_rt_" + $RunId)
New-Item -ItemType Directory -Force -Path $Work | Out-Null

$InputDir = Join-Path $Work "input_tree"
$SnapDir  = Join-Path $Work "snapshot_tree_v1"
$OutDir   = Join-Path $Work "restored_tree"

New-Item -ItemType Directory -Force -Path $InputDir | Out-Null

# deterministic tree (no randomness)
New-Item -ItemType Directory -Force -Path (Join-Path $InputDir "a") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InputDir "a\b") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InputDir "empty_dir") | Out-Null

# file1: 1.25 MiB pattern
$f1 = Join-Path $InputDir "a\one.bin"
$size1 = 1310720
$buf1 = New-Object byte[] $size1
for($i=0; $i -lt $size1; $i++){ $buf1[$i] = [byte](($i * 17 + 3) % 256) }
[IO.File]::WriteAllBytes($f1,$buf1)

# file2: 3.5 MiB pattern (same as earlier)
$f2 = Join-Path $InputDir "a\b\two.bin"
$size2 = 3670016
$buf2 = New-Object byte[] $size2
for($i=0; $i -lt $size2; $i++){ $buf2[$i] = [byte](($i * 131 + 17) % 256) }
[IO.File]::WriteAllBytes($f2,$buf2)

# file3: small text
$f3 = Join-Path $InputDir "root.txt"
[IO.File]::WriteAllText($f3, "triad-tree-v1`nline2`n", (New-Object System.Text.UTF8Encoding($false)))

# baseline hashes
$in = @{}
$in["a/one.bin"]    = Sha256HexFile $f1
$in["a/b/two.bin"]  = Sha256HexFile $f2
$in["root.txt"]     = Sha256HexFile $f3

# capture
$sid = & $Capture -RepoRoot $RepoRoot -InputDir $InputDir -OutDir $SnapDir -BlockSize 1048576

# restore workflow
$plan = & $Prep   -RepoRoot $RepoRoot -SnapshotDir $SnapDir -OutDir $OutDir
$sr   = & $Verify -RepoRoot $RepoRoot -PlanPath $plan
& $Commit -RepoRoot $RepoRoot -PlanPath $plan

# final file checks
$rf1 = Join-Path $OutDir "a\one.bin"
$rf2 = Join-Path $OutDir "a\b\two.bin"
$rf3 = Join-Path $OutDir "root.txt"
if((Sha256HexFile $rf1) -ne $in["a/one.bin"]){ Die "ROUNDTRIP_FILE_MISMATCH: a/one.bin" }
if((Sha256HexFile $rf2) -ne $in["a/b/two.bin"]){ Die "ROUNDTRIP_FILE_MISMATCH: a/b/two.bin" }
if((Sha256HexFile $rf3) -ne $in["root.txt"]){ Die "ROUNDTRIP_FILE_MISMATCH: root.txt" }

# empty dir preserved
if(-not (Test-Path -LiteralPath (Join-Path $OutDir "empty_dir") -PathType Container)){ Die "ROUNDTRIP_EMPTY_DIR_MISSING" }

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "TRIAD TREE ROUNDTRIP SELFTEST: PASS"     -ForegroundColor Green
Write-Host ("snapshot_id:   {0}" -f [string]$sid)    -ForegroundColor Cyan
Write-Host ("semantic_root: {0}" -f [string]$sr)     -ForegroundColor Cyan
Write-Host ("work_dir:      {0}" -f $Work)           -ForegroundColor DarkGray
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
