param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$BaseManifest,
  [Parameter(Mandatory=$true)][string]$CompareManifest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

if(-not (Test-Path $BaseManifest)){ Die ("BASE_MANIFEST_NOT_FOUND: " + $BaseManifest) }
if(-not (Test-Path $CompareManifest)){ Die ("COMPARE_MANIFEST_NOT_FOUND: " + $CompareManifest) }

$base = Get-Content $BaseManifest -Raw | ConvertFrom-Json
$comp = Get-Content $CompareManifest -Raw | ConvertFrom-Json

$baseMap = @{}
foreach($e in $base.entries){
  $baseMap[$e.path] = $e
}

$compMap = @{}
foreach($e in $comp.entries){
  $compMap[$e.path] = $e
}

$added = New-Object System.Collections.Generic.List[string]
$removed = New-Object System.Collections.Generic.List[string]
$modified = New-Object System.Collections.Generic.List[string]

# detect added + modified
foreach($path in $compMap.Keys){
  if(-not $baseMap.ContainsKey($path)){
    [void]$added.Add($path)
  } else {
    $b = $baseMap[$path]
    $c = $compMap[$path]

    if($b.sha256 -ne $c.sha256 -or $b.size -ne $c.size){
      [void]$modified.Add($path)
    }
  }
}

# detect removed
foreach($path in $baseMap.Keys){
  if(-not $compMap.ContainsKey($path)){
    [void]$removed.Add($path)
  }
}

Write-Host ("ADDED: " + $added.Count)
Write-Host ("REMOVED: " + $removed.Count)
Write-Host ("MODIFIED: " + $modified.Count)

if($added.Count -gt 0){
  Write-Host "--- ADDED ---"
  $added | Sort-Object | ForEach-Object { Write-Host $_ }
}

if($removed.Count -gt 0){
  Write-Host "--- REMOVED ---"
  $removed | Sort-Object | ForEach-Object { Write-Host $_ }
}

if($modified.Count -gt 0){
  Write-Host "--- MODIFIED ---"
  $modified | Sort-Object | ForEach-Object { Write-Host $_ }
}

Write-Host "TRIAD_DIFF_V1_OK"
