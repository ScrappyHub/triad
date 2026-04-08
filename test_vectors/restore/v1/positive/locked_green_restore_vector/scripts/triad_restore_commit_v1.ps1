param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$PlanPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function ReadJson([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  $raw = (Get-Content -Raw -LiteralPath $Path -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
  try { $raw | ConvertFrom-Json } catch { Die ("JSON_PARSE_FAIL: " + $Path + " :: " + $_.Exception.Message) }
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die ("MISSING_REPO: " + $RepoRoot) }
if(-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)){ Die ("MISSING_PLAN: " + $PlanPath) }

$plan = ReadJson $PlanPath
if([string]$plan.schema -ne "triad.restore_plan.v1"){ Die ("PLAN_SCHEMA_UNEXPECTED: " + [string]$plan.schema) }

$OutFile = [string]$plan.out_file
$TmpFile = [string]$plan.tmp_file

if([string]::IsNullOrWhiteSpace($OutFile)){ Die "PLAN_OUTFILE_EMPTY" }
if([string]::IsNullOrWhiteSpace($TmpFile)){ Die "PLAN_TMP_EMPTY" }
if(-not (Test-Path -LiteralPath $TmpFile -PathType Leaf)){ Die ("MISSING_TMP: " + $TmpFile) }

# Commit is ONLY a move/replace. Caller must run triad_restore_verify_v1.ps1 first.
$parent = Split-Path -Parent $OutFile
if($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)){
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

if(Test-Path -LiteralPath $OutFile -PathType Leaf){
  Remove-Item -LiteralPath $OutFile -Force
}

Move-Item -LiteralPath $TmpFile -Destination $OutFile -Force

Write-Host "OK: TRIAD RESTORE COMMIT v1" -ForegroundColor Green
Write-Host ("out_file: {0}" -f $OutFile) -ForegroundColor Cyan
