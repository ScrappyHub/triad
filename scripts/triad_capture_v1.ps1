param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$InputDir,
  [Parameter(Mandatory=$true)][string]$OutputManifest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

if(-not (Test-Path $InputDir)){ Die ("INPUT_DIR_NOT_FOUND: " + $InputDir) }
if(Test-Path $OutputManifest){ Die ("OUTPUT_ALREADY_EXISTS: " + $OutputManifest) }

$InputDir = (Resolve-Path $InputDir).Path

$entries = New-Object System.Collections.Generic.List[object]

$files = Get-ChildItem -LiteralPath $InputDir -Recurse -File

foreach($f in $files){
  $full = $f.FullName
  $rel = $full.Substring($InputDir.Length).TrimStart('\')

  $bytes = [System.IO.File]::ReadAllBytes($full)
  $sha = [System.BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  ).Replace("-","").ToLowerInvariant()

  $entries.Add([pscustomobject]@{
    path = $rel
    size = $bytes.Length
    sha256 = $sha
  })
}

$sorted = $entries | Sort-Object path

$idParts = New-Object System.Collections.Generic.List[string]
[void]$idParts.Add("triad.capture.manifest.v1")
[void]$idParts.Add([string]$sorted.Count)

foreach($e in $sorted){
  [void]$idParts.Add(($e.path + "|" + $e.sha256 + "|" + $e.size))
}

$joined = ($idParts.ToArray() -join "`n")

$root = [System.BitConverter]::ToString(
  [System.Security.Cryptography.SHA256]::Create().ComputeHash(
    [System.Text.Encoding]::UTF8.GetBytes($joined)
  )
).Replace("-","").ToLowerInvariant()

$manifest = [pscustomobject]@{
  manifest_version = "triad.capture.manifest.v1"
  root_hash = $root
  entry_count = $sorted.Count
  entries = $sorted
}

$manifest | ConvertTo-Json -Depth 6 | Out-File -Encoding utf8 $OutputManifest

Write-Host ("ROOT_HASH: " + $root)
Write-Host ("ENTRY_COUNT: " + $sorted.Count)
Write-Host "TRIAD_CAPTURE_V1_OK"
