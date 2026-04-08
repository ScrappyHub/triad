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
$Capture    = Join-Path $ScriptsDir "triad_capture_v1.ps1"
$Prep       = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
$Verify     = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
$Commit     = Join-Path $ScriptsDir "triad_restore_commit_v1.ps1"

foreach($p in @($Capture,$Prep,$Verify,$Commit)){
  ParseGate $p
}

# Work dir
$WorkRoot = Join-Path $ScriptsDir "_work"
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
$RunId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss") + "_" + ([Guid]::NewGuid().ToString("N"))
$Work  = Join-Path $WorkRoot ("restorewf_" + $RunId)
New-Item -ItemType Directory -Force -Path $Work | Out-Null

$Input   = Join-Path $Work "payload.bin"
$SnapDir = Join-Path $Work "snapshot_v1"
$OutFile = Join-Path $Work "restored.bin"

# deterministic payload (same as prior selftest)
$size = 3670016
$buf  = New-Object byte[] $size
for($i=0; $i -lt $size; $i++){
  $buf[$i] = [byte](($i * 131 + 17) % 256)
}
[IO.File]::WriteAllBytes($Input,$buf)
$inHash = Sha256HexFile $Input

# Capture
$sid = & $Capture -RepoRoot $RepoRoot -InputFile (Split-Path -Parent $Input) -OutDir $SnapDir -BlockSize 1048576

# Prepare -> Verify -> Commit
$plan = & $Prep   -RepoRoot $RepoRoot -SnapshotDir $SnapDir -OutFile $OutFile
Write-Host ("TRACE_BEFORE_VERIFY_V55S: verify=" + $Verify) -ForegroundColor DarkGray
Write-Host "TRACE_BEFORE_VERIFY_CALL_V55S" -ForegroundColor DarkGray
$vs   = & $Verify -RepoRoot $RepoRoot -PlanPath $plan
Write-Host "TRACE_AFTER_VERIFY_CALL_V55S" -ForegroundColor DarkGray
& $Commit -RepoRoot $RepoRoot -PlanPath $plan

# Final check
if(-not (Test-Path -LiteralPath $OutFile -PathType Leaf)){ Die "RESTORED_MISSING" }
$outHash = Sha256HexFile $OutFile
if($outHash -ne $inHash){ Die ("WORKFLOW_SHA_MISMATCH: in=" + $inHash + " out=" + $outHash) }

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "TRIAD RESTORE WORKFLOW SELFTEST: PASS"  -ForegroundColor Green
Write-Host ("snapshot_id: {0}" -f [string]$sid)     -ForegroundColor Cyan
Write-Host ("sha256:       {0}" -f $outHash)        -ForegroundColor Cyan
Write-Host ("plan:         {0}" -f $plan)           -ForegroundColor DarkGray
Write-Host ("work_dir:     {0}" -f $Work)           -ForegroundColor DarkGray
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
