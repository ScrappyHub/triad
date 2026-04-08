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
    $msg = ($errs | Select-Object -First 12 | ForEach-Object { $_.Message }) -join " | "
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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v54r_" + $ts)
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
if ([string]::IsNullOrWhiteSpace($GoodPath)) { Die "NO_PARSE_OK_PRE_PATCH_FOUND_V54R" }
Write-Host ("restore_from: " + $GoodPath) -ForegroundColor DarkGray

# Restore known-good
$rest = (Get-Content -Raw -LiteralPath $GoodPath -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
Write-Utf8NoBomLf $Target $rest
Parse-GateFile_Parser $Target
Write-Host ("RESTORED_OK: " + $Target) -ForegroundColor Green

# ---- Apply minimal SAFE traces (no regex touching function declarations) ----
$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

if ($txt -match '(?im)PATCH_SAFE_TRACES_V54R') {
  Parse-GateFile_Parser $Target
  Write-Host ("OK: v54r already present: " + $Target) -ForegroundColor Green
  return
}

$before = $txt

# Insert heartbeat (fixed ms) after first Set-StrictMode -Version Latest
$m = [regex]::Match($txt, '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
if (-not $m.Success) { Die "NO_SET_STRICTMODE_ANCHOR_FOUND_V54R" }
$pos = $m.Index + $m.Length

$hb = @(
  '',
  '# PATCH_SAFE_TRACES_V54R',
  '$script:__triad_hb_sw = [System.Diagnostics.Stopwatch]::StartNew()',
  '$script:__triad_hb_timer = New-Object System.Timers.Timer',
  '$script:__triad_hb_timer.Interval = 2000',
  '$script:__triad_hb_timer.AutoReset = $true',
  '$null = Register-ObjectEvent -InputObject $script:__triad_hb_timer -EventName Elapsed -Action {',
  '  try {',
  '    $ms = 0',
  '    try { $ms = [int]$script:__triad_hb_sw.ElapsedMilliseconds } catch { $ms = 0 }',
  '    Write-Host ("HB: +" + $ms + "ms") -ForegroundColor DarkGray',
  '  } catch { }',
  '}',
  '$script:__triad_hb_timer.Start()',
  '# /PATCH_SAFE_TRACES_V54R',
  ''
) -join "`n"

$txt = $txt.Substring(0,$pos) + "`n" + $hb + $txt.Substring($pos)

# Insert TRACE after the first *source line* containing expected + len=0 + sha256=
# IMPORTANT: This touches only the single line that *contains those tokens*, it does not rewrite functions.
$needle = '(?im)^(?<indent>\s*)(?<line>.*expected:\s*.*len\s*=\s*0.*sha256\s*=.*)$'
$inserted = $false
$txt = [regex]::Replace($txt, $needle, {
  param($m)
  if($inserted){ return $m.Value }
  $inserted = $true
  $indent = $m.Groups["indent"].Value
  return @(
    $m.Groups["line"].Value,
    ($indent + 'Write-Host "TRACE_AFTER_EXPECTED_LEN0_V54R" -ForegroundColor DarkGray')
  ) -join "`n"
})

if (-not $inserted) { Die "PATCH_NO_EXPECTED_LEN0_LINE_FOUND_V54R" }
if ($txt -eq $before) { Die "PATCH_NO_CHANGE_V54R" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile_Parser $Target
Write-Host ("FINAL_OK: restored parse-ok + patched SAFE traces (v54r): " + $Target) -ForegroundColor Green
