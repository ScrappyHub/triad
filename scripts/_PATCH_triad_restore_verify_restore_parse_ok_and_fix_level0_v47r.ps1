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
  if (-not $t.EndsWith("`n")) {
    $t += "`n"
  }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Parse-GateText([string]$Text){
  $null = [ScriptBlock]::Create($Text)
}

function Parse-GateFile([string]$Path){
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  Parse-GateText $raw
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) {
  Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir)
}

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v47r_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) {
  Die ("MISSING_TARGET: " + $Target)
}
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".broken_pre_restore")) -Force

# ---- Find newest parse-ok pre_patch backup ----
$Candidates = Get-ChildItem -LiteralPath $ScriptsDir -Directory -Force |
  Where-Object { $_.Name -like "_backup_triad_restore_verify_*" } |
  Sort-Object FullName -Descending

$GoodPath = ""
foreach($d in $Candidates){
  $p = Join-Path $d.FullName "triad_restore_verify_v1.ps1.pre_patch"
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
  $raw = (Get-Content -Raw -LiteralPath $p -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
  try {
    Parse-GateText $raw
    $GoodPath = $p
    break
  } catch {
    continue
  }
}

if ([string]::IsNullOrWhiteSpace($GoodPath)) {
  Die "NO_PARSE_OK_PRE_PATCH_FOUND_V47R"
}

Write-Host ("restore_from: " + $GoodPath) -ForegroundColor DarkGray

# Restore known-good
$rest = (Get-Content -Raw -LiteralPath $GoodPath -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
Write-Utf8NoBomLf $Target $rest
Parse-GateFile $Target

# ---- Now apply the safe level[0] fix on the restored script ----
$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

# Idempotency for the FIX itself
if ($txt -match '(?im)PATCH_LEVEL0_EMPTY_TO_ZEROS_V47R') {
  Parse-GateFile $Target
  Write-Host ("OK: v47r already present: " + $Target) -ForegroundColor Green
  return
}

# Ensure AtOrNull exists (insert after first Set-StrictMode -Version Latest if missing)
if ($txt -notmatch '(?im)^\s*function\s+AtOrNull\s*\(') {
  $m = [regex]::Match($txt, '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
  if (-not $m.Success) { Die "NO_SET_STRICTMODE_ANCHOR_FOUND_FOR_AtOrNull_V47R" }
  $pos = $m.Index + $m.Length

  $helper = @(
    '',
    '# PATCH_LEVEL0_EMPTY_TO_ZEROS_V47R',
    'function AtOrNull([Parameter(Mandatory=$true)]$Arr,[Parameter(Mandatory=$true)][int]$Index){',
    '  if($null -eq $Arr){ return $null }',
    '  $a = @(@($Arr))',
    '  if($Index -lt 0){ return $null }',
    '  if($Index -ge $a.Count){ return $null }',
    '  return $a[$Index]',
    '}',
    ''
  ) -join "`n"

  $txt = $txt.Substring(0,$pos) + "`n" + $helper + $txt.Substring($pos)
}

$before = $txt

# Replace the exact failing line with a safe block.
$needle = '(?im)^\s*\(\s*\$level\s*\[\s*0\s*\]\s*\|\s*ForEach-Object\s*\{\s*\$_\.ToString\("x2"\)\s*\}\s*\)\s*-join\s*""\s*$'

$replacement = @(
  '  # PATCH_LEVEL0_EMPTY_TO_ZEROS_V47R',
  '  $__b = AtOrNull $level 0',
  '  if($null -eq $__b){',
  '    ("0" * 64)',
  '  } else {',
  '    ($__b | ForEach-Object { $_.ToString("x2") }) -join ""',
  '  }',
  '  # /PATCH_LEVEL0_EMPTY_TO_ZEROS_V47R'
) -join "`n"

$txt = [regex]::Replace($txt, $needle, $replacement)

if ($txt -eq $before) {
  Die "PATCH_NO_CHANGE_V47R: could not find the $level[0] hex line in restored script"
}

Write-Utf8NoBomLf $Target $txt
Parse-GateFile $Target
Write-Host ("FINAL_OK: restored parse-ok + fixed level[0] empty case: " + $Target) -ForegroundColor Green
