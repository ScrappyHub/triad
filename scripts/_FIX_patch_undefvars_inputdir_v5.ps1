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
$BackupDir = Join-Path $ScriptsDir ("_backup_patch_undefvars_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_fix")) -Force

# Read/normalize
$enc = New-Object System.Text.UTF8Encoding($false)
$txt = [System.IO.File]::ReadAllText($Target,$enc)
$txt = $txt.Replace("`r`n","`n").Replace("`r","`n")

# Detect literal $InputDir assignment WITHOUT ever expanding $InputDir in this fixer
$patAssign = '(?m)^\s*\$InputDir\s*='
if(-not [regex]::IsMatch($txt,$patAssign)){
  $lines = @($txt -split "`n",-1)
  $out = New-Object System.Collections.Generic.List[string]
  $inserted = $false
  for($i=0;$i -lt $lines.Count;$i++){
    $ln = $lines[$i]
    [void]$out.Add($ln)
    if(-not $inserted -and $ln -match '^[\t ]*Set-StrictMode[\t ]+-Version[\t ]+Latest[\t ]*$'){
      [void]$out.Add('`$InputDir = $null')
      $inserted = $true
    }
  }
  if(-not $inserted){ Die "ANCHOR_NOT_FOUND: Set-StrictMode -Version Latest" }
  $txt = ($out.ToArray() -join "`n")
}

Write-Utf8NoBomLf $Target $txt
Parse-Gate $Target
Write-Host "OK: patch undefvar fix applied + parse-gated" -ForegroundColor Green
Write-Host ("target:     {0}" -f $Target) -ForegroundColor Cyan
Write-Host ("backup_dir: {0}" -f $BackupDir) -ForegroundColor DarkGray

if($RunPatch){
  Write-Host "Running patch now..." -ForegroundColor Yellow
  & $Target -RepoRoot $RepoRoot
  Write-Host "OK: patch executed" -ForegroundColor Green
}
