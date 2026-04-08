param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function ParseGate([string]$Path){
  [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Path -Encoding UTF8)) | Out-Null
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  Die ("MISSING_REPO: " + $RepoRoot)
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
$LibPath    = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
$MakePath   = Join-Path $ScriptsDir "make_allowed_signers_v1.ps1"
$ShowPath   = Join-Path $ScriptsDir "show_identity_v1.ps1"
$TrustPath  = Join-Path $RepoRoot  "proofs\trust\trust_bundle.json"
$Signers    = Join-Path $RepoRoot  "proofs\trust\allowed_signers"

# --------------------------------------------------
# 1) Parse-gate all scripts
# --------------------------------------------------
foreach($p in @($LibPath,$MakePath,$ShowPath)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Die ("MISSING_SCRIPT: " + $p)
  }
  ParseGate $p
}

# --------------------------------------------------
# 2) Run make/show (in-process, no nested shells)
# --------------------------------------------------
& $MakePath -RepoRoot $RepoRoot
& $ShowPath -RepoRoot $RepoRoot

# --------------------------------------------------
# 3) Verify deterministic allowed_signers
# --------------------------------------------------

# Hard reset then dot-source lib to get functions
Remove-Variable -Name NL_LIB_LOADED -Scope Global -ErrorAction SilentlyContinue
Remove-Item -Path Function:\NL-* -ErrorAction SilentlyContinue
. $LibPath

if(-not (Get-Command NL-LoadTrustBundle -ErrorAction SilentlyContinue)){
  Die "LIB_LOAD_FAILED"
}

$tb       = NL-LoadTrustBundle $RepoRoot
$expected = NL-DeriveAllowedSignersText $tb
$actual   = (Get-Content -Raw -LiteralPath $Signers -Encoding UTF8).Replace("`r`n","`n")

if($expected -ne $actual){
  Die "ALLOWED_SIGNERS_MISMATCH (non-deterministic output)"
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Signers).Hash.ToLowerInvariant()

# --------------------------------------------------
# 4) PASS block
# --------------------------------------------------
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "NEVERLOST SELFTEST: PASS"              -ForegroundColor Green
Write-Host "allowed_signers_sha256: $hash"         -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
