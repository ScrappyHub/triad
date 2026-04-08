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
function Parse-GateText_Parser([string]$Text){
  $tok=$null; $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tok,[ref]$err)
  $errs=@(); if($err -ne $null){ $errs=@(@($err)) }
  if($errs.Count -gt 0){
    $msg = ($errs | Select-Object -First 12 | ForEach-Object { $_.Message }) -join " | "
    throw ("PARSE_GATE_FAIL: " + $msg)
  }
}
function Parse-GateFile_Parser([string]$Path){
  $raw = (Get-Content -Raw -LiteralPath $Path -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
  Parse-GateText_Parser $raw
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
if(-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)){ Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }

$Target = Join-Path $ScriptsDir "_selftest_triad_restore_workflow_v1.ps1"
if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){ Die ("MISSING_TARGET: " + $Target) }

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_selftest_restorewf_v55s_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force
Write-Host ("backupdir: " + $BackupDir) -ForegroundColor DarkGray

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
if($txt -match '(?im)TRACE_BEFORE_VERIFY_V55S'){
  Parse-GateFile_Parser $Target
  Write-Host ("OK: v55s already present: " + $Target) -ForegroundColor Green
  return
}

# Anchor on the verify invocation line: "$vs   = & $Verify -RepoRoot $RepoRoot -PlanPath $plan"
$needle = '(?im)^(?<indent>\s*)\$vs\s*=\s*&\s*\$Verify\b.*$'
$m = [regex]::Match($txt, $needle, [System.Text.RegularExpressions.RegexOptions]::Multiline)
if(-not $m.Success){ Die "NO_VERIFY_CALLSITE_FOUND_V55S" }

$callLine = $m.Value
$indent = $m.Groups["indent"].Value

$rep = @(
  ($indent + 'Write-Host ("TRACE_BEFORE_VERIFY_V55S: verify=" + $Verify) -ForegroundColor DarkGray'),
  ($indent + 'Write-Host "TRACE_BEFORE_VERIFY_CALL_V55S" -ForegroundColor DarkGray'),
  $callLine,
  ($indent + 'Write-Host "TRACE_AFTER_VERIFY_CALL_V55S" -ForegroundColor DarkGray')
) -join "`n"

$txt2 = [regex]::Replace($txt, $needle, [System.Text.RegularExpressions.MatchEvaluator]{
  param($mm)
  return $rep
}, 1)

Write-Utf8NoBomLf $Target $txt2
Parse-GateFile_Parser $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v55s: trace around verify)") -ForegroundColor Green
