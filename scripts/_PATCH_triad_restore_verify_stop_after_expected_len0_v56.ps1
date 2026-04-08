param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
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
  $tok=$null; $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tok,[ref]$err)
  $errs=@()
  if($err -ne $null){ $errs=@(@($err)) }
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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v56_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force
Write-Host ("backupdir: " + $BackupDir) -ForegroundColor DarkGray

$raw = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
if($raw -match 'TRACE_STOP_AFTER_EXPECTED_LEN0_V56'){
  Parse-GateFile_Parser $Target
  Write-Host ("OK: v56 already present: " + $Target) -ForegroundColor Green
  return
}

$lines = New-Object System.Collections.Generic.List[string]
foreach($ln in ($raw -split "`n", 0, 'SimpleMatch')){
  [void]$lines.Add($ln)
}

$idx = -1
for($i=0; $i -lt $lines.Count; $i++){
  $line = $lines[$i]
  if($line -match 'expected:' -and $line -match 'len\s*=\s*0' -and $line -match 'sha256\s*='){
    $idx = $i
    break
  }
}

if($idx -lt 0){ Die "EXPECTED_LEN0_SHA256_LINE_NOT_FOUND_V56" }

Write-Host ("MATCH_LINE_INDEX_V56: " + ($idx + 1)) -ForegroundColor DarkGray
Write-Host "CONTEXT_AFTER_MATCH_V56:" -ForegroundColor DarkGray
$max = [Math]::Min($lines.Count - 1, $idx + 8)
for($j=$idx; $j -le $max; $j++){
  Write-Host ((("{0,4}" -f ($j + 1)) + ": " + $lines[$j])) -ForegroundColor DarkGray
}

$insert = 'throw "TRACE_STOP_AFTER_EXPECTED_LEN0_V56"'
$lines.Insert($idx + 1, $insert)

$out = ($lines.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $out
Parse-GateFile_Parser $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v56: stop immediately after expected len=0 sha256)") -ForegroundColor Green
