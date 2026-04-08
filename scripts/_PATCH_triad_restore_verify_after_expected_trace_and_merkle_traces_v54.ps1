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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v54_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

if ($txt -match '(?im)PATCH_AFTER_EXPECTED_TRACE_V54') {
  Parse-GateFile_Parser $Target
  Write-Host ("OK: v54 already present: " + $Target) -ForegroundColor Green
  return
}

$before = $txt

# 1) Insert fixed heartbeat after first Set-StrictMode
$m = [regex]::Match($txt, '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
if (-not $m.Success) { Die "NO_SET_STRICTMODE_ANCHOR_FOUND_V54" }
$pos = $m.Index + $m.Length

$hb = @(
  '',
  '# PATCH_AFTER_EXPECTED_TRACE_V54',
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
  '# /PATCH_AFTER_EXPECTED_TRACE_V54',
  ''
) -join "`n"

$txt = $txt.Substring(0,$pos) + "`n" + $hb + $txt.Substring($pos)

# 2) Inject trace after ANY Write-Host/Write-Output that contains the literal "expected:" and "len=0" and "sha256="
# (works whether it is string concat, format string, or plain literal)
$patExpected = '(?im)^(?<indent>\s*)(?:Write-Output|Write-Host)\b.*expected:\s*.*len\s*=\s*0.*sha256\s*='
$did = $false
$txt = [regex]::Replace($txt, $patExpected, {
  param($m)
  if($script:__triad_v54_expected_done){ return $m.Value }
  $script:__triad_v54_expected_done = $true
  $indent = $m.Groups["indent"].Value
  $did = $true
  return @(
    $m.Value,
    ($indent + 'Write-Host "TRACE_AFTER_EXPECTED_V54" -ForegroundColor DarkGray'),
    ($indent + 'Write-Host "TRACE_BEFORE_NEXT_STEP_V54" -ForegroundColor DarkGray')
  ) -join "`n"
})

# 3) Wrap MerkleRootHex callsites with trace markers (does not change behavior)
# Replace "MerkleRootHex <arg>" and "MerkleRootHex(<arg>)" forms.
$patCall1 = '(?im)\bMerkleRootHex\s*\(\s*([^)]+?)\s*\)'
$txt = [regex]::Replace($txt, $patCall1, '$(Write-Host "TRACE_CALL_MERKLE_V54" -ForegroundColor DarkGray; MerkleRootHex($1))')

$patCall2 = '(?im)\bMerkleRootHex\s+([^\r\n;]+)'
$txt = [regex]::Replace($txt, $patCall2, '$(Write-Host "TRACE_CALL_MERKLE_V54" -ForegroundColor DarkGray; MerkleRootHex $1)')

if ($txt -eq $before) { Die "PATCH_NO_CHANGE_V54: no changes applied (unexpected)" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile_Parser $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v54: robust after-expected trace + fixed heartbeat + merkle call traces)") -ForegroundColor Green
