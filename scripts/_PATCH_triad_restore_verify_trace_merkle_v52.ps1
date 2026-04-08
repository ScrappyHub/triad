param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Parse-GateText_Parser([string]$Text){
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tok, [ref]$err)
  $errs = @()
  if ($err -ne $null) { $errs = @(@($err)) }
  if ($errs.Count -gt 0) {
    $msg = ($errs | Select-Object -First 8 | ForEach-Object { $_.Message }) -join " | "
    throw ("PARSE_GATE_FAIL: " + $msg)
  }
}

function Parse-GateFile_Parser([string]$Path){
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  $raw = $raw.Replace("`r`n","`n").Replace("`r","`n")
  Parse-GateText_Parser $raw
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v52_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

if ($txt -match '(?im)PATCH_TRACE_MERKLE_V52') {
  Parse-GateFile_Parser $Target
  Write-Host ("OK: v52 already present: " + $Target) -ForegroundColor Green
  return
}

$before = $txt

# 1) Rename the original MerkleRootHex -> _MerkleRootHex_Impl (first occurrence only)
$reDef = New-Object System.Text.RegularExpressions.Regex('(?im)^\s*function\s+MerkleRootHex\s*\(', [System.Text.RegularExpressions.RegexOptions]::Multiline)
if (-not $reDef.IsMatch($txt)) { Die "NO_MERKLEROOTHEX_DEF_FOUND_V52" }

$txt = $reDef.Replace($txt, 'function _MerkleRootHex_Impl(', 1)

# 2) Insert wrapper function right before the renamed impl
$wrap = @(
  '',
  '# PATCH_TRACE_MERKLE_V52',
  'function MerkleRootHex([string[]]$HexHashesInOrder){',
  '  $n = 0',
  '  try { $n = @(@($HexHashesInOrder)).Count } catch { $n = 0 }',
  '  Write-Host ("TRACE: MerkleRootHex start n=" + $n) -ForegroundColor DarkGray',
  '  $sw = [System.Diagnostics.Stopwatch]::StartNew()',
  '  $r = _MerkleRootHex_Impl $HexHashesInOrder',
  '  $sw.Stop()',
  '  $ms = 0',
  '  try { $ms = [int]$sw.ElapsedMilliseconds } catch { $ms = 0 }',
  '  Write-Host ("TRACE: MerkleRootHex end ms=" + $ms) -ForegroundColor DarkGray',
  '  return $r',
  '}',
  '# /PATCH_TRACE_MERKLE_V52',
  ''
) -join "`n"

# Find the location of the renamed impl and inject wrapper right before it
$idx = $txt.IndexOf('function _MerkleRootHex_Impl(')
if ($idx -lt 0) { Die "INTERNAL_NO_RENAMED_IMPL_FOUND_V52" }

$txt = $txt.Substring(0,$idx) + $wrap + $txt.Substring($idx)

if ($txt -eq $before) { Die "PATCH_NO_CHANGE_V52" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile_Parser $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v52: TRACE wrapper for MerkleRootHex)") -ForegroundColor Green
