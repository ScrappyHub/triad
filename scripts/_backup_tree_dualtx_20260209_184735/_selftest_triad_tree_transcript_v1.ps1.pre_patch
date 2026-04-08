param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function ParseGate([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }
  $null = [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Path -Encoding UTF8))
}

function Sha256HexBytes([byte[]]$Bytes){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $h = $sha.ComputeHash($Bytes)
    ($h | ForEach-Object { $_.ToString("x2") }) -join ""
  } finally { $sha.Dispose() }
}

function Sha256HexText([string]$Text){
  Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($Text))
}

function HexToBytes([string]$Hex){
  if([string]::IsNullOrWhiteSpace($Hex)){ Die "HEX_EMPTY" }
  if(($Hex.Length % 2) -ne 0){ Die ("HEX_ODD_LEN: " + $Hex.Length) }
  $len = $Hex.Length / 2
  $b = New-Object byte[] $len
  for($i=0; $i -lt $len; $i++){
    $b[$i] = [Convert]::ToByte($Hex.Substring($i*2,2),16)
  }
  $b
}

function MerkleRootHex([string[]]$HexHashesInOrder){
  $arr = @(@($HexHashesInOrder))
  if($arr.Count -lt 1){ Die "MERKLE_EMPTY" }

  $level = New-Object System.Collections.Generic.List[byte[]]
  foreach($hx in $arr){ [void]$level.Add((HexToBytes $hx)) }

  while($level.Count -gt 1){
    $next = New-Object System.Collections.Generic.List[byte[]]
    for($i=0; $i -lt $level.Count; $i += 2){
      $a = $level[$i]
      $b = $null
      if(($i+1) -lt $level.Count){ $b = $level[$i+1] } else { $b = $level[$i] }
      $cat = New-Object byte[] ($a.Length + $b.Length)
      [Array]::Copy($a,0,$cat,0,$a.Length)
      [Array]::Copy($b,0,$cat,$a.Length,$b.Length)
      $sha = [System.Security.Cryptography.SHA256]::Create()
      try {
        $h = $sha.ComputeHash($cat)
        [void]$next.Add($h)
      } finally { $sha.Dispose() }
    }
    $level = $next
  }
  ($level[0] | ForEach-Object { $_.ToString("x2") }) -join ""
}

function ReadJson([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  $raw = (Get-Content -Raw -LiteralPath $Path -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
  try { $raw | ConvertFrom-Json } catch { Die ("JSON_PARSE_FAIL: " + $Path + " :: " + $_.Exception.Message) }
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die ("MISSING_REPO: " + $RepoRoot) }

$ScriptsDir = Join-Path $RepoRoot "scripts"
$Capture    = Join-Path $ScriptsDir "triad_capture_tree_v1.ps1"
ParseGate $Capture

# Work dir
$WorkRoot = Join-Path $ScriptsDir "_work"
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
$RunId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss") + "_" + ([Guid]::NewGuid().ToString("N"))
$Work  = Join-Path $WorkRoot ("tree_tx_" + $RunId)
New-Item -ItemType Directory -Force -Path $Work | Out-Null

$InputDir = Join-Path $Work "input_tree"
$SnapDir  = Join-Path $Work "snapshot_tree_v1"

New-Item -ItemType Directory -Force -Path $InputDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InputDir "a") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InputDir "empty_dir") | Out-Null

# deterministic file
$f = Join-Path $InputDir "a\one.bin"
$size = 262144
$buf = New-Object byte[] $size
for($i=0; $i -lt $size; $i++){ $buf[$i] = [byte](($i * 19 + 7) % 256) }
[IO.File]::WriteAllBytes($f,$buf)

# capture
$sid = & $Capture -RepoRoot $RepoRoot -InputDir $InputDir -OutDir $SnapDir -BlockSize 65536

$manifestPath = Join-Path $SnapDir "snapshot.tree.manifest.json"
if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){ Die ("MISSING_MANIFEST: " + $manifestPath) }

$man = ReadJson $manifestPath
if([string]$man.schema -ne "triad.snapshot_tree.v1"){ Die ("MANIFEST_SCHEMA_UNEXPECTED: " + [string]$man.schema) }

# transcript binding MUST exist
$txRel     = [string]$man.transcript.path
$txRootRel = [string]$man.transcript.root_path
if([string]::IsNullOrWhiteSpace($txRel)){ Die "MANIFEST_TRANSCRIPT_PATH_EMPTY" }
if([string]::IsNullOrWhiteSpace($txRootRel)){ Die "MANIFEST_TRANSCRIPT_ROOTPATH_EMPTY" }

$txPath     = Join-Path $SnapDir ($txRel -replace "/","\")
$txRootPath = Join-Path $SnapDir ($txRootRel -replace "/","\")
if(-not (Test-Path -LiteralPath $txPath -PathType Leaf)){ Die ("MISSING_TRANSCRIPT: " + $txPath) }
if(-not (Test-Path -LiteralPath $txRootPath -PathType Leaf)){ Die ("MISSING_TRANSCRIPT_ROOT: " + $txRootPath) }

$expectedRoot = [string]$man.roots.transcript_root
if([string]::IsNullOrWhiteSpace($expectedRoot)){ Die "MANIFEST_TRANSCRIPT_ROOT_EMPTY" }
if($expectedRoot -notmatch "^[0-9a-f]{64}$"){ Die ("MANIFEST_TRANSCRIPT_ROOT_SHAPE_INVALID: " + $expectedRoot) }

$rootFile = (Get-Content -Raw -LiteralPath $txRootPath -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n").Trim()
if($rootFile -ne $expectedRoot){ Die ("TRANSCRIPT_ROOT_FILE_MISMATCH: file=" + $rootFile + " manifest=" + $expectedRoot) }

# Validate chain + per-line hashes + recompute transcript_root
$lines = @(@((Get-Content -LiteralPath $txPath -Encoding UTF8) | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }))
if($lines.Count -lt 1){ Die "TRANSCRIPT_EMPTY" }

$prev = ("0" * 64)
$hashes = New-Object System.Collections.Generic.List[string]

foreach($ln in $lines){
  $o = $null
  try { $o = $ln | ConvertFrom-Json } catch { Die ("TRANSCRIPT_JSON_PARSE_FAIL: " + $_.Exception.Message) }

  $seq = [int]$o.seq
  $ts  = [string]$o.ts_utc
  $ev  = [string]$o.event
  $pv  = [string]$o.prev_sha256
  $dj  = [string]$o.data_json
  $sh  = [string]$o.sha256

  if($pv -ne $prev){ Die ("TRANSCRIPT_PREV_MISMATCH: seq=" + $seq) }

  $basis = ("triad.transcript_line.v1|{0}|{1}|{2}|{3}|{4}" -f $seq,$ts,$ev,$pv,$dj)
  $reh = Sha256HexText $basis
  if($reh -ne $sh){ Die ("TRANSCRIPT_LINE_HASH_MISMATCH: seq=" + $seq) }

  [void]$hashes.Add($sh)
  $prev = $sh
}

$root = MerkleRootHex ($hashes.ToArray())
if($root -ne $expectedRoot){ Die ("TRANSCRIPT_ROOT_MISMATCH: expected=" + $expectedRoot + " got=" + $root) }

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "TRIAD TREE TRANSCRIPT SELFTEST: PASS"    -ForegroundColor Green
Write-Host ("snapshot_id:      {0}" -f [string]$sid) -ForegroundColor Cyan
Write-Host ("transcript_root:  {0}" -f $root)        -ForegroundColor Cyan
Write-Host ("work_dir:         {0}" -f $Work)        -ForegroundColor DarkGray
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
