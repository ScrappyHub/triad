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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v44_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

# Idempotency
if ($txt -match '(?im)PATCH_VERIFY_MANIFEST_NO_BLOCKS_V44') {
  Parse-GateFile $Target
  Write-Host ("OK: v44 already present: " + $Target) -ForegroundColor Green
  return
}

# We want to neutralize any Die/throw of MANIFEST_NO_BLOCKS and replace with WARN + empty blocks.
# Handle common forms:
#   Die "MANIFEST_NO_BLOCKS"
#   Die 'MANIFEST_NO_BLOCKS'
#   throw "MANIFEST_NO_BLOCKS"
#   throw 'MANIFEST_NO_BLOCKS'
$before = $txt

$replacement = @(
  '# PATCH_VERIFY_MANIFEST_NO_BLOCKS_V44',
  'Write-Output "WARN: MANIFEST_NO_BLOCKS (verify fallback: normalize manifest.blocks to empty; plan blocks will drive restore)"',
  '$manifestBlocks = @()',
  '# /PATCH_VERIFY_MANIFEST_NO_BLOCKS_V44'
) -join "`n"

# Replace Die/throw line ONLY (keep surrounding logic intact)
$txt = [regex]::Replace(
  $txt,
  '(?im)^\s*(?:Die|throw)\s+["'']MANIFEST_NO_BLOCKS["'']\s*$',
  $replacement
)

# If nothing changed, try a slightly broader pattern: any line containing MANIFEST_NO_BLOCKS that throws
if ($txt -eq $before) {
  $txt = [regex]::Replace(
    $txt,
    '(?im)^\s*(?:Die|throw)\s+.*MANIFEST_NO_BLOCKS.*$',
    $replacement
  )
}

if ($txt -eq $before) { Die "PATCH_NO_CHANGE_V44: could not find a Die/throw MANIFEST_NO_BLOCKS line to replace (script drift?)" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v44 converted MANIFEST_NO_BLOCKS to WARN + empty blocks)") -ForegroundColor Green
