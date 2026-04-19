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

$items = Get-ChildItem -LiteralPath $InputDir -Recurse -Force

foreach($i in $items){
  $full = $i.FullName
  $rel = $full.Substring($InputDir.Length).TrimStart('\')

  if($i.PSIsContainer){
    $entries.Add([pscustomobject]@{
      path = $rel
      type = "dir"
      size = 0
      sha256 = ""
      last_write = $i.LastWriteTimeUtc.ToString("o")
    })
  } else {
    $bytes = [System.IO.File]::ReadAllBytes($full)
    $sha = [System.BitConverter]::ToString(
      [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    ).Replace("-","").ToLowerInvariant()

    $entries.Add([pscustomobject]@{
      path = $rel
      type = "file"
      size = $bytes.Length
      sha256 = $sha
      last_write = $i.LastWriteTimeUtc.ToString("o")
    })
  }
}

$sorted = $entries | Sort-Object path,type

$idParts = New-Object System.Collections.Generic.List[string]
[void]$idParts.Add("triad.capture.manifest.v2")
[void]$idParts.Add([string]$sorted.Count)

foreach($e in $sorted){
  [void]$idParts.Add(($e.type + "|" + $e.path + "|" + $e.sha256 + "|" + $e.size + "|" + $e.last_write))
}

$joined = ($idParts.ToArray() -join "`n")

$root = [System.BitConverter]::ToString(
  [System.Security.Cryptography.SHA256]::Create().ComputeHash(
    [System.Text.Encoding]::UTF8.GetBytes($joined)
  )
).Replace("-","").ToLowerInvariant()

$manifest = [pscustomobject]@{
  manifest_version = "triad.capture.manifest.v2"
  root_hash = $root
  entry_count = $sorted.Count
  entries = $sorted
}

$manifest | ConvertTo-Json -Depth 6 | Out-File -Encoding utf8 $OutputManifest

Write-Host ("ROOT_HASH: " + $root)
Write-Host ("ENTRY_COUNT: " + $sorted.Count)
Write-Host "TRIAD_CAPTURE_V2_OK"
