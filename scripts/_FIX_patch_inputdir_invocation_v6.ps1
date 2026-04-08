param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [switch]$RunPatch = $true
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Parse-Gate([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }; $null = [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Path -Encoding UTF8)) }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die ("MISSING_REPO: " + $RepoRoot) }
$ScriptsDir = Join-Path $RepoRoot "scripts"
$Target = Join-Path $ScriptsDir "_PATCH_tree_transcript_dual_v1.ps1"
if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){ Die ("MISSING_TARGET_PATCH: " + $Target) }

# Backup
$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_patch_inputdir_cmdpos_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_fix")) -Force

# Read/normalize
$enc = New-Object System.Text.UTF8Encoding($false)
$txt = [System.IO.File]::ReadAllText($Target,$enc)
$txt = $txt.Replace("`r`n","`n").Replace("`r","`n")
$lines = @($txt -split "`n",-1)
$out = New-Object System.Collections.Generic.List[string]
$changed = 0

# Any line that STARTS with "$InputDir" but is NOT an assignment will be commented out.
$patCmdPos = '^[\t ]*\$InputDir(\s+|$)'
for($i=0;$i -lt $lines.Count;$i++){
  $ln = $lines[$i]
  if($ln -match $patCmdPos -and ($ln -notmatch '=')){
    [void]$out.Add("# FIX_V6: disabled stray cmd-position InputDir line: " + $ln)
    $changed++
  } else {
    [void]$out.Add($ln)
  }
}

$txt2 = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $txt2
Parse-Gate $Target
Write-Host "OK: patch cmd-position InputDir lines disabled + parse-gated" -ForegroundColor Green
Write-Host ("target:     {0}" -f $Target) -ForegroundColor Cyan
Write-Host ("backup_dir: {0}" -f $BackupDir) -ForegroundColor DarkGray
Write-Host ("lines_changed: {0}" -f $changed) -ForegroundColor Cyan

if($RunPatch){
  Write-Host "Running patch now..." -ForegroundColor Yellow
  & $Target -RepoRoot $RepoRoot
  Write-Host "OK: patch executed" -ForegroundColor Green
}
