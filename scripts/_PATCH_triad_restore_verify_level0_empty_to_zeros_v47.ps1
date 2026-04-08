param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateFile([string]$Path){
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  $null = [ScriptBlock]::Create($raw)
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v47_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

# Idempotency
if ($txt -match '(?im)PATCH_LEVEL0_EMPTY_TO_ZEROS_V47') {
  Parse-GateFile $Target
  Write-Host ("OK: v47 already present: " + $Target) -ForegroundColor Green
  return
}

# Require AtOrNull (v46 inserted it); if missing, fail fast (we do NOT silently drift).
if ($txt -notmatch '(?im)^\s*function\s+AtOrNull\s*\(') { Die "MISSING_HELPER_AtOrNull_V47: expected from v46" }

$before = $txt

# Replace the exact failing line with a safe, multi-line last-expression block.
# Match (with flexible whitespace):
#   ($level[0] | ForEach-Object { $_.ToString("x2") }) -join ""
$needle = '(?im)^\s*\(\s*\$level\s*\[\s*0\s*\]\s*\|\s*ForEach-Object\s*\{\s*\$_\.ToString\("x2"\)\s*\}\s*\)\s*-join\s*""\s*$'

$replacement = @(
  '  # PATCH_LEVEL0_EMPTY_TO_ZEROS_V47',
  '  $__b = AtOrNull $level 0',
  '  if($null -eq $__b){',
  '    ("0" * 64)',
  '  } else {',
  '    ($__b | ForEach-Object { $_.ToString("x2") }) -join ""',
  '  }',
  '  # /PATCH_LEVEL0_EMPTY_TO_ZEROS_V47'
) -join "`n"

$txt = [regex]::Replace($txt, $needle, $replacement)

if ($txt -eq $before) { Die "PATCH_NO_CHANGE_V47: could not find the exact $level[0] hex line (script drift?)" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v47 makes empty merkle level hex fallback to 0*64)") -ForegroundColor Green
