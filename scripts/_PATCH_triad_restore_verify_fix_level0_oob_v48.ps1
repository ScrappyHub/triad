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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v48_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = Get-Content -Raw -LiteralPath $Target -Encoding UTF8
$txt = $txt.Replace("`r`n","`n").Replace("`r","`n")

if ($txt -match '(?im)PATCH_FIX_LEVEL0_OOB_V48') {
  Parse-GateFile_Parser $Target
  Write-Host ("OK: v48 already present: " + $Target) -ForegroundColor Green
  return
}

# Ensure AtOrNull exists (insert right after first Set-StrictMode -Version Latest)
if ($txt -notmatch '(?im)^\s*function\s+AtOrNull\s*\(') {
  $m = [regex]::Match($txt, '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
  if (-not $m.Success) { Die "NO_SET_STRICTMODE_ANCHOR_FOUND_FOR_ATORNULL_V48" }
  $pos = $m.Index + $m.Length

  $helper = @(
    '',
    '# PATCH_FIX_LEVEL0_OOB_V48',
    'function AtOrNull([Parameter(Mandatory=$true)]$Arr,[Parameter(Mandatory=$true)][int]$Index){',
    '  if($null -eq $Arr){ return $null }',
    '  $a = @(@($Arr))',
    '  if($Index -lt 0){ return $null }',
    '  if($Index -ge $a.Count){ return $null }',
    '  return $a[$Index]',
    '}',
    '# /PATCH_FIX_LEVEL0_OOB_V48',
    ''
  ) -join "`n"

  $txt = $txt.Substring(0,$pos) + "`n" + $helper + $txt.Substring($pos)
} else {
  # still stamp idempotency marker if AtOrNull already exists
  $txt = "# PATCH_FIX_LEVEL0_OOB_V48`n" + $txt
}

$before = $txt

# Replace the exact failing line (single-line statement)
$needle = '(?im)^\s*\(\s*\$level\s*\[\s*0\s*\]\s*\|\s*ForEach-Object\s*\{\s*\$_\.ToString\("x2"\)\s*\}\s*\)\s*-join\s*""\s*$'

$replacement = @(
  '  # PATCH_FIX_LEVEL0_OOB_V48',
  '  $__b = AtOrNull $level 0',
  '  if($null -eq $__b){',
  '    ("0" * 64)',
  '  } else {',
  '    ($__b | ForEach-Object { $_.ToString("x2") }) -join ""',
  '  }',
  '  # /PATCH_FIX_LEVEL0_OOB_V48'
) -join "`n"

$txt = [regex]::Replace($txt, $needle, $replacement)

if ($txt -eq $before) { Die "PATCH_NO_CHANGE_V48: could not find exact level[0] hex line to replace" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile_Parser $Target

Write-Host ("FINAL_OK: patched " + $Target + " (v48: safe level[0] => zeros)") -ForegroundColor Green
