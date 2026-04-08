param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [int]$RunPatch = 0
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  if ([string]::IsNullOrWhiteSpace($Path)) { Die "WRITE_UTF8_PATH_EMPTY" }
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateFile([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }; $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8; $null = [ScriptBlock]::Create($raw) }

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("MISSING_REPO: " + $RepoRoot) }
$ScriptsDir = Join-Path $RepoRoot "scripts"
$Target = Join-Path $ScriptsDir "_PATCH_tree_transcript_dual_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET_PATCH: " + $Target) }

# Backup
$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_gate1_fix_v12_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_fix")) -Force

# Read/normalize
$enc = New-Object System.Text.UTF8Encoding($false)
$txt = [System.IO.File]::ReadAllText($Target,$enc).Replace("`r`n","`n").Replace("`r","`n")

# If already fixed, report success and optionally run patch.
if ($txt -notmatch '`\$InputDir') {
  Parse-GateFile $Target
  Write-Host "OK: Gate1 already clean (no backtick-escaped `$InputDir found) + parse-gated" -ForegroundColor Green
  Write-Host ("target:    {0}" -f $Target) -ForegroundColor Cyan
  Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray
  if ($RunPatch -ne 0) {
    Write-Host "Running dual transcript patch now..." -ForegroundColor Yellow
    & $Target -RepoRoot $RepoRoot
    Write-Host "GATE1_OK: dual transcript patch ran clean" -ForegroundColor Green
  }
  return
}

# Fix: replace ONLY a whole-line assignment starting with backtick-escaped `$InputDir
$badPat = '(?m)^[\t ]*`\$InputDir[\t ]*=[\t ]*\$null[\t ]*$'
$before = ([regex]::Matches($txt,$badPat)).Count
if ($before -lt 1) { Die 'GATE1_V12_NO_MATCH: backtick-escaped assignment not found in expected line form' }
$txt2 = [regex]::Replace($txt,$badPat,'$InputDir = $null')

# Safety: after replacement, ZERO backtick-escaped `$InputDir occurrences may remain
$rem = ([regex]::Matches($txt2,'`\$InputDir')).Count
if ($rem -ne 0) { Die ("GATE1_V12_REMAINING_BACKTICK_INPUTDIR: " + $rem) }

Write-Utf8NoBomLf $Target $txt2
Parse-GateFile $Target
Write-Host "OK: Gate1 v12 removed backtick-escaped `$InputDir assignment + parse-gated patch" -ForegroundColor Green
Write-Host ("target:    {0}" -f $Target) -ForegroundColor Cyan
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray
Write-Host ("fixed_lines_matched: {0}" -f $before) -ForegroundColor Cyan

if ($RunPatch -ne 0) {
  Write-Host "Running dual transcript patch now..." -ForegroundColor Yellow
  & $Target -RepoRoot $RepoRoot
  Write-Host "GATE1_OK: dual transcript patch ran clean" -ForegroundColor Green
}
