param(
  [Parameter(Mandatory=$true)][ValidateSet("make_allowed_signers","show_identity")][string]$Which
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function DumpErr($e){
  Write-Host "=== EXCEPTION ===" -ForegroundColor Red
  Write-Host ("Type: {0}" -f $e.GetType().FullName) -ForegroundColor Red
  Write-Host ("Message: {0}" -f $e.Exception.Message) -ForegroundColor Red

  if($e.InvocationInfo){
    Write-Host "=== INVOCATION ===" -ForegroundColor Yellow
    Write-Host $e.InvocationInfo.PositionMessage -ForegroundColor Yellow
    Write-Host ("ScriptName: {0}" -f $e.InvocationInfo.ScriptName) -ForegroundColor Yellow
    Write-Host ("Line: {0}" -f $e.InvocationInfo.ScriptLineNumber) -ForegroundColor Yellow
  }

  Write-Host "=== SCRIPT STACK ===" -ForegroundColor Yellow
  Write-Host ($e.ScriptStackTrace | Out-String) -ForegroundColor Yellow
}

try{
  if($Which -eq "make_allowed_signers"){
    & (Join-Path $PSScriptRoot "make_allowed_signers_v1.ps1")
  } elseif($Which -eq "show_identity"){
    & (Join-Path $PSScriptRoot "show_identity_v1.ps1") `
      -Principal "single-tenant/local/authority/devbox-1" `
      -KeyId "dev-ed25519-1"
  }
  Write-Host "DIAG: OK" -ForegroundColor Green
}catch{
  DumpErr $_
  exit 1
}
