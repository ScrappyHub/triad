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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v62_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force
Write-Host ("backupdir: " + $BackupDir) -ForegroundColor DarkGray

$raw = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
if($raw -match 'PATCH_REBUILD_TMP_FROM_BLOCKS_V62'){
  Parse-GateFile_Parser $Target
  Write-Host ("OK: v62 already present: " + $Target) -ForegroundColor Green
  return
}

$needle = '(?im)^\s*\$tmpLen\s*=\s*\(Get-Item\s+-LiteralPath\s+\$TmpFile\)\.Length\s*$'
$m = [regex]::Match($raw, $needle, [System.Text.RegularExpressions.RegexOptions]::Multiline)
if(-not $m.Success){ Die "TMP_LEN_LINE_NOT_FOUND_V62" }

$indent = ""
$mi = [regex]::Match($m.Value, '^\s*')
if($mi.Success){ $indent = $mi.Value }

$replacement = @(
  ($indent + '# PATCH_REBUILD_TMP_FROM_BLOCKS_V62'),
  ($indent + '$tmpLen = (Get-Item -LiteralPath $TmpFile).Length'),
  ($indent + 'if(([int64]$tmpLen -eq 0) -and (@(@($blocks)).Count -gt 0)){'),
  ($indent + '  Write-Host "TRACE_REBUILD_TMP_FROM_BLOCKS_V62" -ForegroundColor DarkGray'),
  ($indent + '  $fs = $null'),
  ($indent + '  try {'),
  ($indent + '    $fs = New-Object System.IO.FileStream($TmpFile,[System.IO.FileMode]::Create,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)'),
  ($indent + '    foreach($b in $blocks){'),
  ($indent + '      $rel = [string](PropOf $b "path")'),
  ($indent + '      if([string]::IsNullOrWhiteSpace($rel)){ Die "TMP_REBUILD_BLOCK_PATH_MISSING_V62" }'),
  ($indent + '      $blkPath = Join-Path $SnapshotDir ($rel -replace "/","\")'),
  ($indent + '      if(-not (Test-Path -LiteralPath $blkPath -PathType Leaf)){ Die ("TMP_REBUILD_MISSING_BLOCK_FILE_V62: " + $blkPath) }'),
  ($indent + '      $bytes = [System.IO.File]::ReadAllBytes($blkPath)'),
  ($indent + '      $fs.Write($bytes,0,$bytes.Length)'),
  ($indent + '    }'),
  ($indent + '    $fs.Flush()'),
  ($indent + '  } finally {'),
  ($indent + '    if($null -ne $fs){ $fs.Dispose() }'),
  ($indent + '  }'),
  ($indent + '  $tmpLen = (Get-Item -LiteralPath $TmpFile).Length'),
  ($indent + '  Write-Host ("TRACE_REBUILT_TMP_LEN_V62: " + $tmpLen) -ForegroundColor DarkGray'),
  ($indent + '}'),
  ($indent + '# /PATCH_REBUILD_TMP_FROM_BLOCKS_V62')
) -join "`n"

$out = [regex]::Replace($raw, $needle, [System.Text.RegularExpressions.MatchEvaluator]{ param($mm) $replacement }, 1)

Write-Utf8NoBomLf $Target $out
Parse-GateFile_Parser $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v62: rebuild tmp from blocks before len/sha checks)") -ForegroundColor Green
