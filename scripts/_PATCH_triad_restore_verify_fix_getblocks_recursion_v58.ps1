param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Parse-GateText_Parser([string]$Text){
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tok,[ref]$err)
  $errs = @()
  if($err -ne $null){ $errs = @(@($err)) }
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

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){ Die ("MISSING_TARGET: " + $Target) }

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v58_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force
Write-Host ("backupdir: " + $BackupDir) -ForegroundColor DarkGray

$raw = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
if($raw -match 'PATCH_FIX_GETBLOCKS_RECURSION_V58'){
  Parse-GateFile_Parser $Target
  Write-Host ("OK: v58 already present: " + $Target) -ForegroundColor Green
  return
}

$fnPat = '(?is)function\s+GetBlocksForVerify\s*\(\s*\[Parameter\(Mandatory=\$true\)\]\$Manifest\s*,\s*\[Parameter\(Mandatory=\$true\)\]\$Plan\s*\)\s*\{\s*.*?\n\}'
$fm = [regex]::Match($raw, $fnPat)
if(-not $fm.Success){ Die "GETBLOCKS_FUNCTION_NOT_FOUND_V58" }

$fnNew = @"
function GetBlocksForVerify([Parameter(Mandatory=`$true)]`$Manifest,[Parameter(Mandatory=`$true)]`$Plan){
  # PATCH_FIX_GETBLOCKS_RECURSION_V58
  `$mb = `$null
  try { `$mb = ArrOf `$Manifest "blocks" } catch { `$mb = `$null }
  `$mba = @()
  if(`$mb -ne `$null){ `$mba = @(@(`$mb)) }
  if(`$mba.Count -gt 0){ return `$mb }

  `$pb = `$null
  try { `$pb = ArrOf `$Plan "blocks" } catch { `$pb = `$null }
  if(`$pb -eq `$null){ return @() }
  return @(@(`$pb))
}
"@

$out = $raw.Substring(0,$fm.Index) + $fnNew + $raw.Substring($fm.Index + $fm.Length)

Write-Utf8NoBomLf $Target $out
Parse-GateFile_Parser $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v58: fixed GetBlocksForVerify recursion)") -ForegroundColor Green
