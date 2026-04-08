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
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) {
  Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir)
}

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v47s_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) {
  Die ("MISSING_TARGET: " + $Target)
}
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".broken_pre_restore")) -Force

# Enumerate backups newest-first
$Candidates = Get-ChildItem -LiteralPath $ScriptsDir -Directory -Force |
  Where-Object { $_.Name -like "_backup_triad_restore_verify_*" } |
  Sort-Object Name -Descending

$GoodPath = ""
$Checked = 0
foreach($d in $Candidates){
  $p = Join-Path $d.FullName "triad_restore_verify_v1.ps1.pre_patch"
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }

  $Checked += 1
  $raw = Get-Content -Raw -LiteralPath $p -Encoding UTF8
  $raw = $raw.Replace("`r`n","`n").Replace("`r","`n")

  try {
    Parse-GateText_Parser $raw
    $GoodPath = $p
    break
  } catch {
    continue
  }
}

Write-Host ("checked_prepatch: " + $Checked) -ForegroundColor DarkGray

if ([string]::IsNullOrWhiteSpace($GoodPath)) {
  Die "NO_PARSE_OK_PRE_PATCH_FOUND_V47S"
}

Write-Host ("restore_from: " + $GoodPath) -ForegroundColor DarkGray

# Restore known-good and parse-gate it with Parser
$rest = Get-Content -Raw -LiteralPath $GoodPath -Encoding UTF8
$rest = $rest.Replace("`r`n","`n").Replace("`r","`n")

Write-Utf8NoBomLf $Target $rest
Parse-GateFile_Parser $Target

Write-Host ("RESTORED_OK: " + $Target) -ForegroundColor Green
