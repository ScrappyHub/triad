param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$thisDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libPath = Join-Path $thisDir "_lib_neverlost_v1.ps1"
if(-not (Test-Path -LiteralPath $libPath)){ throw ("LIB_MISSING: " + $libPath) }
Remove-Variable -Name NL_LIB_LOADED -Scope Global -ErrorAction SilentlyContinue
Remove-Item -Path Function:\NL-* -ErrorAction SilentlyContinue
. $libPath
if(-not (Get-Command NL-GetDefaultPrincipalAndKey -ErrorAction SilentlyContinue)){ throw ("LIB_DOTSOURCE_FAILED: NL-GetDefaultPrincipalAndKey :: " + $libPath) }
$info = NL-GetDefaultPrincipalAndKey $RepoRoot
Write-Host "NeverLost Identity (v1)" -ForegroundColor Green
Write-Host ("principal: {0}" -f $info.principal) -ForegroundColor Cyan
Write-Host ("key_id:    {0}" -f $info.key_id) -ForegroundColor Cyan
Write-Host ("pubkey:    {0}" -f $info.pubkey) -ForegroundColor Cyan
