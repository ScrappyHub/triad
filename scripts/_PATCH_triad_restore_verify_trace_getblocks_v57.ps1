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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v57_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force
Write-Host ("backupdir: " + $BackupDir) -ForegroundColor DarkGray

$raw = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
if($raw -match 'TRACE_BEFORE_GETBLOCKS_V57'){
  Parse-GateFile_Parser $Target
  Write-Host ("OK: v57 already present: " + $Target) -ForegroundColor Green
  return
}

$lines = New-Object System.Collections.Generic.List[string]
foreach($ln in ($raw -split "`n", 0, 'SimpleMatch')){
  [void]$lines.Add($ln)
}

$idx = -1
for($i = 0; $i -lt $lines.Count; $i++){
  if($lines[$i].Trim() -eq '$blocks = @(@((GetBlocksForVerify $man $plan)))'){
    $idx = $i
    break
  }
}

if($idx -lt 0){ Die "GETBLOCKS_LINE_NOT_FOUND_V57" }

$indent = ""
$m = [regex]::Match($lines[$idx], '^\s*')
if($m.Success){ $indent = $m.Value }

$replacement = @(
  ($indent + 'Write-Host "TRACE_BEFORE_GETBLOCKS_V57" -ForegroundColor DarkGray'),
  ($indent + '$blocks = @(@((GetBlocksForVerify $man $plan)))'),
  ($indent + 'Write-Host "TRACE_AFTER_GETBLOCKS_V57" -ForegroundColor DarkGray'),
  ($indent + 'Write-Host ("TRACE_BLOCKS_COUNT_V57: " + $blocks.Count) -ForegroundColor DarkGray'),
  ($indent + 'Write-Host "TRACE_BEFORE_BLOCK_FOREACH_V57" -ForegroundColor DarkGray')
)

$lines.RemoveAt($idx)
for($k = $replacement.Count - 1; $k -ge 0; $k--){
  $lines.Insert($idx, $replacement[$k])
}

$out = ($lines.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $out
Parse-GateFile_Parser $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v57: traced GetBlocksForVerify boundary)") -ForegroundColor Green
