param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$thisDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libPath = Join-Path $thisDir "_lib_neverlost_v1.ps1"
if(-not (Test-Path -LiteralPath $libPath)){ throw ("LIB_MISSING: " + $libPath) }
Remove-Variable -Name NL_LIB_LOADED -Scope Global -ErrorAction SilentlyContinue
Remove-Item -Path Function:\NL-* -ErrorAction SilentlyContinue
. $libPath
if(-not (Get-Command NL-WriteAllowedSigners -ErrorAction SilentlyContinue)){ throw ("LIB_DOTSOURCE_FAILED: NL-WriteAllowedSigners :: " + $libPath) }
$out    = NL-WriteAllowedSigners $RepoRoot
$tbPath = NL-TrustBundlePath $RepoRoot
$asPath = NL-AllowedSignersPath $RepoRoot
Write-Host "OK: allowed_signers written deterministically" -ForegroundColor Green
Write-Host ("trust_bundle:    {0}" -f $tbPath) -ForegroundColor Cyan
Write-Host ("allowed_signers: {0}" -f $asPath) -ForegroundColor Cyan
Write-Host ("trust_bundle_sha256:    {0}" -f (NL-Sha256HexFile $tbPath)) -ForegroundColor DarkGray
Write-Host ("allowed_signers_sha256: {0}" -f (NL-Sha256HexFile $asPath)) -ForegroundColor DarkGray
