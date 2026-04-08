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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v40_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

# --- Step 1: restore from newest v39 backup (because v39 likely left target syntactically broken)
$bak = Get-ChildItem -LiteralPath $ScriptsDir -Directory -ErrorAction Stop |
  Where-Object { $_.Name -match '^_backup_triad_restore_verify_v39_' } |
  Sort-Object Name -Descending |
  Select-Object -First 1

if ($null -eq $bak) { Die "NO_V39_BACKUP_DIR_FOUND (expected _backup_triad_restore_verify_v39_*)" }

$restoreSrc = Join-Path $bak.FullName "triad_restore_verify_v1.ps1.pre_patch"
if (-not (Test-Path -LiteralPath $restoreSrc -PathType Leaf)) { Die ("NO_V39_PREPATCH_FOUND: " + $restoreSrc) }

Copy-Item -LiteralPath $restoreSrc -Destination $Target -Force
Write-Host ("RESTORED_FROM_V39_BACKUP: " + $restoreSrc) -ForegroundColor Yellow

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

# Idempotency
if ($txt -match '(?im)PATCH_LENOF_GLOBAL_V40') {
  Parse-GateFile $Target
  Write-Host ("OK: v40 already present: " + $Target) -ForegroundColor Green
  return
}

# --- Step 2: install LenOf helper (expression-safe length getter)
if ($txt -notmatch '(?im)^\s*function\s+LenOf\s*\(') {
  $m = [regex]::Match($txt, '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
  if (-not $m.Success) { Die "NO_SET_STRICTMODE_ANCHOR_FOUND_FOR_LENOF_V40" }
  $pos = $m.Index + $m.Length

  $helper = @(
    '',
    '# PATCH_LENOF_GLOBAL_V40',
    'function LenOf([Parameter(Mandatory=$true)]$Obj){',
    '  try {',
    '    if ($null -eq $Obj) { return $null }',
    '    # string/array/etc',
    '    try {',
    '      $pLen = $Obj.PSObject.Properties["Length"]',
    '      if ($null -ne $pLen) { return $pLen.Value }',
    '    } catch { }',
    '    # JSON-ish: "length" (lowercase)',
    '    try {',
    '      $pLen2 = $Obj.PSObject.Properties["length"]',
    '      if ($null -ne $pLen2) { return $pLen2.Value }',
    '    } catch { }',
    '    return $null',
    '  } catch { return $null }',
    '}',
    ''
  ) -join "`n"

  $txt = $txt.Substring(0,$pos) + "`n" + $helper + $txt.Substring($pos)
} else {
  $txt = "# PATCH_LENOF_GLOBAL_V40`n" + $txt
}

$before = $txt

# --- Step 3: rewrite ALL $var.length and $var.Length -> (LenOf $var)
# This is parse-safe everywhere (inside +, args, arithmetic).
$txt = [regex]::Replace(
  $txt,
  '(?im)(\$(?:script:|global:|local:)?[A-Za-z_][A-Za-z0-9_]*)\.(length|Length)\b',
  '(LenOf $1)'
)

if ($txt -eq $before) { Die "PATCH_NO_CHANGE_V40: no `$.length/`$.Length patterns found to rewrite" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v40 restored-from-v39 + global LenOf rewrite of `$.length/`$.Length)") -ForegroundColor Green
