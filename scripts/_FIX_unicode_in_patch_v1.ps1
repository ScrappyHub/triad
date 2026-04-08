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
$BackupDir = Join-Path $ScriptsDir ("_backup_patch_unicodefix_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_fix")) -Force

# Read as UTF-8 (no BOM), normalize line endings to LF for deterministic parse
$enc = New-Object System.Text.UTF8Encoding($false)
$txt = [System.IO.File]::ReadAllText($Target,$enc)
$txt = $txt.Replace("`r`n","`n").Replace("`r","`n")

# Replace mojibake and non-ASCII punctuation that can break PS string literals
# Common offenders observed in console output: â€” (mojibake em dash)
$repls = @(
  @("â€”","--"),
  @("—","--"),
  @("â€“","-"),
  @("–","-"),
  @("“",""""),
  @("”",""""),
)
foreach($r in $repls){ $txt = $txt.Replace([string]$r[0],[string]$r[1]) }

Write-Utf8NoBomLf $Target $txt
Parse-Gate $Target
Write-Host "OK: unicode/mojibake sanitized + parse-gated" -ForegroundColor Green
Write-Host ("target:     {0}" -f $Target) -ForegroundColor Cyan
Write-Host ("backup_dir: {0}" -f $BackupDir) -ForegroundColor DarkGray

if($RunPatch){
  Write-Host "Running patch now..." -ForegroundColor Yellow
  & $Target -RepoRoot $RepoRoot
  Write-Host "OK: patch executed" -ForegroundColor Green
}
