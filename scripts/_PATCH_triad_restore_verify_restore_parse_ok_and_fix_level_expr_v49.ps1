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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v49_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".broken_pre_restore")) -Force

# ---- Find newest parse-ok pre_patch backup ----
$Candidates = Get-ChildItem -LiteralPath $ScriptsDir -Directory -Force |
  Where-Object { $_.Name -like "_backup_triad_restore_verify_*" } |
  Sort-Object FullName -Descending

$GoodPath = ""
$checked = 0
foreach($d in $Candidates){
  $p = Join-Path $d.FullName "triad_restore_verify_v1.ps1.pre_patch"
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
  $checked++
  $raw = (Get-Content -Raw -LiteralPath $p -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
  try {
    Parse-GateText_Parser $raw
    $GoodPath = $p
    break
  } catch { continue }
}

Write-Host ("checked_prepatch: " + $checked) -ForegroundColor DarkGray
if ([string]::IsNullOrWhiteSpace($GoodPath)) { Die "NO_PARSE_OK_PRE_PATCH_FOUND_V49" }
Write-Host ("restore_from: " + $GoodPath) -ForegroundColor DarkGray

# Restore known-good
$rest = (Get-Content -Raw -LiteralPath $GoodPath -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
Write-Utf8NoBomLf $Target $rest
Parse-GateFile_Parser $Target
Write-Host ("RESTORED_OK: " + $Target) -ForegroundColor Green

# ---- Now apply expression-safe fix (works inside if(...) ) ----
$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

if ($txt -match '(?im)PATCH_FIX_LEVEL_EXPR_V49') {
  Parse-GateFile_Parser $Target
  Write-Host ("OK: v49 already present: " + $Target) -ForegroundColor Green
  return
}

# Ensure AtOrNull exists
if ($txt -notmatch '(?im)^\s*function\s+AtOrNull\s*\(') {
  $m = [regex]::Match($txt, '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
  if (-not $m.Success) { Die "NO_SET_STRICTMODE_ANCHOR_FOUND_FOR_ATORNULL_V49" }
  $pos = $m.Index + $m.Length

  $helper = @(
    '',
    '# PATCH_FIX_LEVEL_EXPR_V49',
    'function AtOrNull([Parameter(Mandatory=$true)]$Arr,[Parameter(Mandatory=$true)][int]$Index){',
    '  if($null -eq $Arr){ return $null }',
    '  $a = @(@($Arr))',
    '  if($Index -lt 0){ return $null }',
    '  if($Index -ge $a.Count){ return $null }',
    '  return $a[$Index]',
    '}',
    '# /PATCH_FIX_LEVEL_EXPR_V49',
    ''
  ) -join "`n"

  $txt = $txt.Substring(0,$pos) + "`n" + $helper + $txt.Substring($pos)
} else {
  # stamp marker safely at top
  $txt = "# PATCH_FIX_LEVEL_EXPR_V49`n" + $txt
}

$before = $txt

# Replace the expression ANYWHERE (not whole line). This is safe inside if($null -eq <expr>)
$exprNeedle = '\(\s*\$level\s*\[\s*0\s*\]\s*\|\s*ForEach-Object\s*\{\s*\$_\.ToString\("x2"\)\s*\}\s*\)\s*-join\s*""'

$exprReplacement = '$( $__b = AtOrNull $level 0; if($null -eq $__b){("0"*64)} else {($__b | ForEach-Object { $_.ToString("x2") }) -join ""} )'

$txt = [regex]::Replace($txt, $exprNeedle, $exprReplacement)

if ($txt -eq $before) { Die "PATCH_NO_CHANGE_V49: could not find the level[0] hex expression to replace" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile_Parser $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v49: expression-safe level[0] => zeros)") -ForegroundColor Green
