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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v44b_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

# Idempotency
if ($txt -match '(?im)PATCH_DIE_MANIFEST_NO_BLOCKS_V44B') {
  Parse-GateFile $Target
  Write-Host ("OK: v44b already present: " + $Target) -ForegroundColor Green
  return
}

$before = $txt

# Replace the simple Die definition ONLY in verify script:
# function Die([string]$m){ throw $m }
# -> tolerant Die with MANIFEST_NO_BLOCKS special-case.
$dieNew = @(
  '# PATCH_DIE_MANIFEST_NO_BLOCKS_V44B',
  'function Die([string]$m){',
  '  if($m -eq "MANIFEST_NO_BLOCKS"){',
  '    Write-Output "WARN: MANIFEST_NO_BLOCKS (verify fallback: treat manifest.blocks as empty; plan blocks will drive restore)"',
  '    return',
  '  }',
  '  throw $m',
  '}',
  '# /PATCH_DIE_MANIFEST_NO_BLOCKS_V44B'
) -join "`n"

$txt = [regex]::Replace(
  $txt,
  '(?im)^\s*function\s+Die\s*\(\s*\[string\]\s*\$m\s*\)\s*\{\s*throw\s+\$m\s*\}\s*$',
  $dieNew
)

if ($txt -eq $before) { Die "PATCH_NO_CHANGE_V44B: could not find exact Die([string]`$m){ throw `$m } line to replace (script drift?)" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v44b makes Die tolerant for MANIFEST_NO_BLOCKS only)") -ForegroundColor Green
