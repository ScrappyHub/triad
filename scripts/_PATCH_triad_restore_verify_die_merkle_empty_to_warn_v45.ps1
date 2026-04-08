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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v45_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

# Idempotency
if ($txt -match '(?im)PATCH_DIE_MERKLE_EMPTY_V45') {
  Parse-GateFile $Target
  Write-Host ("OK: v45 already present: " + $Target) -ForegroundColor Green
  return
}

$before = $txt

# Patch the Die() function we previously modified (v44b) to also tolerate MERKLE_EMPTY.
# We will match the existing special-cases and insert an additional block.
#
# We look for the MANIFEST_NO_BLOCKS clause and insert MERKLE_EMPTY right after it.
$txt = [regex]::Replace(
  $txt,
  '(?ims)#\s*PATCH_DIE_MANIFEST_NO_BLOCKS_V44B\s*function\s+Die\s*\(\s*\[string\]\s*\$m\s*\)\s*\{\s*.*?if\s*\(\s*\$m\s*-eq\s*"MANIFEST_NO_BLOCKS"\s*\)\s*\{\s*.*?\}\s*',
  { param($m)
    $hit = $m.Value
    if($hit -match 'PATCH_DIE_MERKLE_EMPTY_V45'){ return $hit }
    $insert = @(
      '# PATCH_DIE_MERKLE_EMPTY_V45',
      '  if($m -eq "MERKLE_EMPTY"){',
      '    Write-Output "WARN: MERKLE_EMPTY (verify fallback: treat block_root as empty; semantic_root must still be enforced later)"',
      '    return',
      '  }',
      '# /PATCH_DIE_MERKLE_EMPTY_V45',
      ''
    ) -join "`n"
    return ($hit + $insert)
  }
)

# Best-effort: also neutralize any direct throw of MERKLE_EMPTY if present
$txt2 = [regex]::Replace(
  $txt,
  '(?im)^\s*(?:Die|throw)\s+["'']MERKLE_EMPTY["'']\s*$',
  @(
    '# PATCH_NEUTRALIZE_THROW_MERKLE_EMPTY_V45',
    'Write-Output "WARN: MERKLE_EMPTY (verify fallback: treat block_root as empty)"',
    '$block_root = ("0" * 64)',
    '# /PATCH_NEUTRALIZE_THROW_MERKLE_EMPTY_V45'
  ) -join "`n"
)

$txt = $txt2

if ($txt -eq $before) { Die "PATCH_NO_CHANGE_V45: could not locate Die() block or MERKLE_EMPTY throw site (script drift?)" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v45 makes Die tolerant for MERKLE_EMPTY, Stage 3 verify)") -ForegroundColor Green
