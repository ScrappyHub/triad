param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SnapshotDir,
  [Parameter(Mandatory=$true)][string]$OutFile
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Sha256HexFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die ("MISSING_REPO: " + $RepoRoot) }
if(-not (Test-Path -LiteralPath $SnapshotDir -PathType Container)){ Die ("MISSING_SNAPSHOT_DIR: " + $SnapshotDir) }

$manifestPath = Join-Path $SnapshotDir "snapshot.manifest.json"
if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){ Die ("MISSING_MANIFEST: " + $manifestPath) }

$raw = (Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
try { $man = $raw | ConvertFrom-Json } catch { Die ("MANIFEST_JSON_PARSE_FAIL: " + $_.Exception.Message) }

if([string]$man.schema -ne "triad.snapshot.v1"){ Die ("MANIFEST_SCHEMA_UNEXPECTED: " + [string]$man.schema) }

$expectedLen = [int64]$man.source.length
$expectedSha = [string]$man.source.sha256

$blocks = @(@($man.blocks))
if($blocks.Count -lt 1){ Die "MANIFEST_NO_BLOCKS" }

# transactional restore: write to temp then move
$parent = Split-Path -Parent $OutFile
if($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)){
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
}
$tmp = ($OutFile + ".triad_tmp_" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss") + "_" + ([Guid]::NewGuid().ToString("N")))

$ofs = [System.IO.File]::Open($tmp,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)
try {
  foreach($b in $blocks){
    $sha = [string]$b.sha256
    $rel = [string]$b.path
    if([string]::IsNullOrWhiteSpace($sha)){ Die "BLOCK_SHA_EMPTY" }
    if([string]::IsNullOrWhiteSpace($rel)){ Die ("BLOCK_PATH_EMPTY: " + $sha) }

    $blkPath = Join-Path $SnapshotDir ($rel -replace "/","\")
    if(-not (Test-Path -LiteralPath $blkPath -PathType Leaf)){ Die ("MISSING_BLOCK_FILE: " + $blkPath) }

    $bytes = [IO.File]::ReadAllBytes($blkPath)
    $ofs.Write($bytes,0,$bytes.Length)
  }
} finally {
  $ofs.Dispose()
}

$len = (Get-Item -LiteralPath $tmp).Length
if([int64]$len -ne $expectedLen){
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  Die ("RESTORE_LEN_MISMATCH: got=" + $len + " expected=" + $expectedLen)
}

$sha = Sha256HexFile $tmp
if($sha -ne $expectedSha){
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  Die ("RESTORE_SHA_MISMATCH: got=" + $sha + " expected=" + $expectedSha)
}

# commit
if(Test-Path -LiteralPath $OutFile -PathType Leaf){
  Remove-Item -LiteralPath $OutFile -Force
}
Move-Item -LiteralPath $tmp -Destination $OutFile -Force

Write-Host "OK: TRIAD RESTORE v1" -ForegroundColor Green
Write-Host ("out_file:      {0}" -f $OutFile) -ForegroundColor Cyan
Write-Host ("out_sha256:    {0}" -f $sha) -ForegroundColor DarkGray
Write-Host ("out_length:    {0}" -f $len) -ForegroundColor DarkGray
