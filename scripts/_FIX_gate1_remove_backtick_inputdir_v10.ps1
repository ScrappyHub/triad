param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [bool]$RunPatch = $true
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
$BackupDir = Join-Path $ScriptsDir ("_backup_gate1_fix_v10_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_fix")) -Force

# Read/normalize
$enc = New-Object System.Text.UTF8Encoding($false)
$txt = [System.IO.File]::ReadAllText($Target,$enc)
$txt = $txt.Replace("`r`n","`n").Replace("`r","`n")

# Fix: remove ONLY a leading literal backtick before $InputDir assignment (line like: `"$InputDir = $null`")
$badPat = '(?m)^[\t ]*`\$InputDir[\t ]*=[\t ]*\$null[\t ]*$'
$good   = '$InputDir = $null'
$before = ([regex]::Matches($txt,$badPat)).Count
if ($before -lt 1) { Die "GATE1_V10_NO_MATCH: did not find exact bad line (`$InputDir = $null) to fix" }
$txt2 = [regex]::Replace($txt,$badPat,$good)

# Safety: after replacement, ZERO occurrences of backtick-escaped `$InputDir may remain anywhere in the file
$remCount = ([regex]::Matches($txt2,'`\$InputDir')).Count
if ($remCount -ne 0) { Die ("GATE1_V10_REMAINING_BACKTICK_INPUTDIR: " + $remCount) }

Write-Utf8NoBomLf $Target $txt2
Parse-GateFile $Target
Write-Host "OK: Gate1 v10 removed stray backtick before $InputDir assignment + parse-gated patch" -ForegroundColor Green
Write-Host ("target:    {0}" -f $Target) -ForegroundColor Cyan
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray
Write-Host ("fixed_lines_matched: {0}" -f $before) -ForegroundColor Cyan

if ($RunPatch) {
  Write-Host "Running dual transcript patch now..." -ForegroundColor Yellow
  & $Target -RepoRoot $RepoRoot
  Write-Host "GATE1_OK: dual transcript patch ran clean" -ForegroundColor Green
}
