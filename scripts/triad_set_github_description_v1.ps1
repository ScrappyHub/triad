param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$Owner = "",
  [Parameter(Mandatory=$false)][string]$Name = "triad"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

$gh = Get-Command gh.exe -ErrorAction SilentlyContinue
if($null -eq $gh){ Die "GH_CLI_NOT_FOUND" }

if([string]::IsNullOrWhiteSpace($Owner)){
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  if($null -ne $git){
    Push-Location $RepoRoot
    try {
      $remote = $null
      try { $remote = (& $git.Source remote get-url origin 2>$null) } catch { $remote = $null }
    } finally {
      Pop-Location
    }

    if(-not [string]::IsNullOrWhiteSpace($remote)){
      if($remote -match 'github\.com[:/]+([^/]+)/([^/.]+)(?:\.git)?$'){
        $Owner = $Matches[1]
        if([string]::IsNullOrWhiteSpace($Name)){ $Name = $Matches[2] }
      }
    }
  }
}

if([string]::IsNullOrWhiteSpace($Owner)){ Die "OWNER_REQUIRED" }
if([string]::IsNullOrWhiteSpace($Name)){ Die "NAME_REQUIRED" }

$repo = $Owner + "/" + $Name
$description = "Deterministic restore substrate for capture, prepare, verify, and transactional commit."

& $gh.Source repo edit $repo --description $description | Out-Host
Write-Host ("GITHUB_DESCRIPTION_OK: " + $repo) -ForegroundColor Green
