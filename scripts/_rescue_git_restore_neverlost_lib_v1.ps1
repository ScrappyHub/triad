param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$LibRelPath = "scripts\_lib_neverlost_v1.ps1"
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

if(-not (Test-Path -LiteralPath $RepoRoot)){ Die ("MISSING_REPO: " + $RepoRoot) }

$lib = Join-Path $RepoRoot $LibRelPath
if(-not (Test-Path -LiteralPath $lib)){ Die ("MISSING_LIB_PATH: " + $lib) }

# Must have git repo
$gitDir = Join-Path $RepoRoot ".git"
if(-not (Test-Path -LiteralPath $gitDir)){ Die ("NO_GIT_REPO: " + $RepoRoot + " (missing .git)") }

Push-Location $RepoRoot
try {
  # Confirm git exists
  $gitOk = $true
  try { git --version | Out-Null } catch { $gitOk = $false }
  if(-not $gitOk){ Die "GIT_NOT_FOUND: git is not available on PATH" }

  # Backup current corrupted lib (for forensics)
  $ts = Get-Date -Format "yyyyMMdd_HHmmss"
  $bak = $lib + ".corrupt_" + $ts
  Copy-Item -LiteralPath $lib -Destination $bak -Force
  if(-not (Test-Path -LiteralPath $bak)){ Die ("BACKUP_FAILED: " + $bak) }

  # Try restore (newer git), then fallback to checkout
  $restored = $false
  try {
    git restore --source=HEAD -- $LibRelPath | Out-Null
    $restored = $true
  } catch {
    $restored = $false
  }

  if(-not $restored){
    try {
      git checkout -- $LibRelPath | Out-Null
      $restored = $true
    } catch {
      $restored = $false
    }
  }

  if(-not $restored){
    Die ("GIT_RESTORE_FAILED: could not restore " + $LibRelPath + " from HEAD")
  }

  # Hard parse gate restored lib
  $txt = Get-Content -LiteralPath $lib -Raw -Encoding UTF8
  [ScriptBlock]::Create($txt) | Out-Null

  Write-Host "RESTORE_OK: _lib_neverlost_v1.ps1 restored from git HEAD + parses" -ForegroundColor Green
  Write-Host ("corrupt_backup: {0}" -f $bak) -ForegroundColor Cyan
  Write-Host ("lib:           {0}" -f $lib) -ForegroundColor Cyan

} finally {
  Pop-Location
}
