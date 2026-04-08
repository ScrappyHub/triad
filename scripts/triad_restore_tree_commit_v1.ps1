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
if([string]$plan.schema -ne "triad.restore_tree_plan.v1"){ Die ("PLAN_SCHEMA_UNEXPECTED: " + [string]$plan.schema) }

$OutDir = [string]$plan.out_dir
$TmpDir = [string]$plan.tmp_dir

if([string]::IsNullOrWhiteSpace($OutDir)){ Die "PLAN_OUTDIR_EMPTY" }
if([string]::IsNullOrWhiteSpace($TmpDir)){ Die "PLAN_TMPDIR_EMPTY" }
if(-not (Test-Path -LiteralPath $TmpDir -PathType Container)){ Die ("MISSING_TMP_DIR: " + $TmpDir) }

$parent = Split-Path -Parent $OutDir
if($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)){
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

# Commit is ONLY a swap/replace. Caller must run triad_restore_tree_verify_v1.ps1 first.
if(Test-Path -LiteralPath $OutDir -PathType Container){
  Remove-Item -LiteralPath $OutDir -Recurse -Force
}
Move-Item -LiteralPath $TmpDir -Destination $OutDir -Force

Write-Host "OK: TRIAD RESTORE TREE COMMIT v1" -ForegroundColor Green
Write-Host ("out_dir: {0}" -f $OutDir) -ForegroundColor Cyan
