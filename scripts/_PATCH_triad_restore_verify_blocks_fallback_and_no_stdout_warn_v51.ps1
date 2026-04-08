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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v51_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

if ($txt -match '(?im)PATCH_BLOCKS_FALLBACK_NO_STDOUT_V51') {
  Parse-GateFile_Parser $Target
  Write-Host ("OK: v51 already present: " + $Target) -ForegroundColor Green
  return
}

$beforeAll = $txt

# -------------------------------------------------------------------
# (A) Stop stdout pollution: convert any Write-Output WARN: MERKLE_EMPTY
#     (inside our prior patch blocks) to Write-Host (NOT output stream).
# -------------------------------------------------------------------
$reWarn = New-Object System.Text.RegularExpressions.Regex('(?im)^\s*Write-Output\s+"WARN:\s+MERKLE_EMPTY[^"]*"\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
$txt = $reWarn.Replace($txt, { param($m) '    Write-Host "WARN: MERKLE_EMPTY (verify fallback: use plan.blocks if present; otherwise treat block_root as empty)" -ForegroundColor DarkYellow' })

# Also convert any other MERKLE_EMPTY Write-Output lines that match looser forms
$reWarn2 = New-Object System.Text.RegularExpressions.Regex('(?im)^\s*Write-Output\s+"WARN:\s+MERKLE_EMPTY[^"]*"\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
$txt = $reWarn2.Replace($txt, { param($m) 'Write-Host "WARN: MERKLE_EMPTY (verify fallback)" -ForegroundColor DarkYellow' })

# -------------------------------------------------------------------
# (B) Ensure verify uses plan.blocks if manifest.blocks missing/empty
#     Replace: ArrOf <manifestExpr> "blocks"  => GetBlocksForVerify <manifestExpr> $plan
# -------------------------------------------------------------------

# Insert helper if missing (after first Set-StrictMode -Version Latest)
if ($txt -notmatch '(?im)^\s*function\s+GetBlocksForVerify\s*\(') {
  $m = [regex]::Match($txt, '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
  if (-not $m.Success) { Die "NO_SET_STRICTMODE_ANCHOR_FOUND_V51" }
  $pos = $m.Index + $m.Length

  $helper = @(
    '',
    '# PATCH_BLOCKS_FALLBACK_NO_STDOUT_V51',
    'function GetBlocksForVerify([Parameter(Mandatory=$true)]$Manifest,[Parameter(Mandatory=$true)]$Plan){',
    '  $mb = $null',
    '  try { $mb = ArrOf $Manifest "blocks" } catch { $mb = $null }',
    '  $mba = @()',
    '  if($mb -ne $null){ $mba = @(@($mb)) }',
    '  if($mba.Count -gt 0){ return $mb }',
    '  $pb = $null',
    '  try { $pb = ArrOf $Plan "blocks" } catch { $pb = $null }',
    '  return $pb',
    '}',
    '# /PATCH_BLOCKS_FALLBACK_NO_STDOUT_V51',
    ''
  ) -join "`n"

  $txt = $txt.Substring(0,$pos) + "`n" + $helper + $txt.Substring($pos)
} else {
  # marker at top if helper already exists
  $txt = "# PATCH_BLOCKS_FALLBACK_NO_STDOUT_V51`n" + $txt
}

# Replace only the exact ArrOf ... "blocks" callsites (not arbitrary "blocks" text)
# NOTE: this assumes verify has $plan in scope (it does in this script path).
$reArrBlocks = New-Object System.Text.RegularExpressions.Regex('(?ims)ArrOf\s+(\$[A-Za-z_][A-Za-z0-9_]*)\s+"blocks"')
$txt2 = $reArrBlocks.Replace($txt, { param($m) ('GetBlocksForVerify ' + $m.Groups[1].Value + ' $plan') })

$txt = $txt2

if ($txt -eq $beforeAll) { Die "PATCH_NO_CHANGE_V51: no changes applied (unexpected drift?)" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile_Parser $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v51: blocks fallback to plan + no stdout warn)") -ForegroundColor Green
