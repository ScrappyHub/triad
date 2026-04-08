param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Ensure-Dir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ throw "ENSURE_DIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ Ensure-Dir $dir }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Parse-GateFile([string]$Path){
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  $errs = @()
  if($err -ne $null){ $errs = @(@($err)) }
  if($errs.Count -gt 0){
    $msg = ($errs | Select-Object -First 12 | ForEach-Object { $_.Message }) -join " | "
    throw ("PARSE_GATE_FAIL: " + $msg)
  }
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
$Target = Join-Path $ScriptsDir "_selftest_triad_restore_workflow_v1.ps1"
if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){ Die ("MISSING_TARGET: " + $Target) }

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_selftest_v65_" + $ts)
Ensure-Dir $BackupDir
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force
Write-Host ("backupdir: " + $BackupDir) -ForegroundColor DarkGray

$raw = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

if($raw -notmatch 'PATCH_SELFTEST_CLEANUP_V65'){
  $raw = "# PATCH_SELFTEST_CLEANUP_V65`n" + $raw
  $raw = [regex]::Replace($raw,'(?im)^\s*Write-Host\s+\("TRACE_BEFORE_VERIFY_V55S:.*\r?\n?','')
  $raw = [regex]::Replace($raw,'(?im)^\s*Write-Host\s+"TRACE_BEFORE_VERIFY_CALL_V55S".*\r?\n?','')
  $raw = [regex]::Replace($raw,'(?im)^\s*Write-Host\s+"TRACE_AFTER_VERIFY_CALL_V55S".*\r?\n?','')
  $raw = [regex]::Replace($raw,'(\r?\n){3,}',"`n`n")
  Write-Utf8NoBomLf $Target $raw
}

Parse-GateFile $Target
Write-Host ("SELFTEST_CLEANUP_OK: " + $Target) -ForegroundColor Green
