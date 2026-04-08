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
$Restore    = Join-Path $ScriptsDir "triad_restore_v1.ps1"

foreach($p in @($Capture,$Restore)){
  ParseGate $p
}

# Deterministic work dir
$WorkRoot = Join-Path $ScriptsDir "_work"
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
$RunId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss") + "_" + ([Guid]::NewGuid().ToString("N"))
$Work  = Join-Path $WorkRoot ("roundtrip_" + $RunId)
New-Item -ItemType Directory -Force -Path $Work | Out-Null

$Input   = Join-Path $Work "payload.bin"
$SnapDir = Join-Path $Work "snapshot_v1"
$OutFile = Join-Path $Work "restored.bin"

# Write deterministic payload bytes (3.5 MiB) without randomness
$size = 3670016
$buf  = New-Object byte[] $size
for($i=0; $i -lt $size; $i++){
  $buf[$i] = [byte](($i * 131 + 17) % 256)
}
[IO.File]::WriteAllBytes($Input,$buf)

$inHash = Sha256HexFile $Input

# Capture (binds to NeverLost identity through lib)
$sid = & $Capture -RepoRoot $RepoRoot -InputFile (Split-Path -Parent $Input) -OutDir $SnapDir -BlockSize 1048576

# Restore + verify
& $Restore -RepoRoot $RepoRoot -SnapshotDir $SnapDir -OutFile $OutFile

$outHash = Sha256HexFile $OutFile
if($outHash -ne $inHash){ Die ("ROUNDTRIP_SHA_MISMATCH: in=" + $inHash + " out=" + $outHash) }

# byte-for-byte check
$bin = [IO.File]::ReadAllBytes($Input)
$bou = [IO.File]::ReadAllBytes($OutFile)
if($bin.Length -ne $bou.Length){ Die ("ROUNDTRIP_LEN_MISMATCH: in=" + $bin.Length + " out=" + $bou.Length) }
for($i=0; $i -lt $bin.Length; $i++){
  if($bin[$i] -ne $bou[$i]){ Die ("ROUNDTRIP_BYTE_MISMATCH_AT: " + $i) }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "TRIAD ROUNDTRIP SELFTEST: PASS"         -ForegroundColor Green
Write-Host ("snapshot_id: {0}" -f [string]$sid)     -ForegroundColor Cyan
Write-Host ("sha256:       {0}" -f $outHash)        -ForegroundColor Cyan
Write-Host ("work_dir:     {0}" -f $Work)           -ForegroundColor DarkGray
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
