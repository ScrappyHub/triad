param(
  [Parameter(Mandatory=$true,Position=0)]
  [string]$Command
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Cli = Join-Path $RepoRoot "scripts\triad_cli_v1.ps1"

if(-not (Test-Path -LiteralPath $Cli)){
  throw "TRIAD_CLI_NOT_FOUND"
}

# pass through
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $Cli `
  -RepoRoot $RepoRoot `
  -Command $Command

if($LASTEXITCODE -ne 0){
  throw "TRIAD_CLI_FAILED"
}