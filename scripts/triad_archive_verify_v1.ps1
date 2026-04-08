param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ArchiveDir
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Read-Utf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  return (Get-Content -Raw -LiteralPath $Path -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
}

function Sha256HexBytes([byte[]]$Bytes){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
  } finally {
    $sha.Dispose()
  }
  return ([BitConverter]::ToString($hash)).Replace("-","").ToLowerInvariant()
}

function Sha256HexFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [System.IO.File]::OpenRead($Path)
    try {
      $hash = $sha.ComputeHash($fs)
    } finally {
      $fs.Dispose()
    }
  } finally {
    $sha.Dispose()
  }
  return ([BitConverter]::ToString($hash)).Replace("-","").ToLowerInvariant()
}

function To-CanonJson([object]$Value){
  if($null -eq $Value){ return 'null' }

  if($Value -is [string]){
    return ($Value | ConvertTo-Json -Compress)
  }

  if(($Value -is [int]) -or ($Value -is [long]) -or ($Value -is [double]) -or ($Value -is [decimal]) -or ($Value -is [float])){
    return ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture,'{0}',$Value))
  }

  if($Value -is [bool]){
    if($Value){ return 'true' } else { return 'false' }
  }

  if(($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string]) -and -not ($Value -is [System.Collections.IDictionary]) -and -not ($Value -is [psobject])){
    $parts = New-Object System.Collections.Generic.List[string]
    foreach($item in $Value){
      [void]$parts.Add((To-CanonJson $item))
    }
    return ('[' + ($parts.ToArray() -join ',') + ']')
  }

  $pairs = New-Object System.Collections.Generic.List[string]
  $props = @()

  if($Value -is [System.Collections.IDictionary]){
    foreach($k in $Value.Keys){
      $props += [pscustomobject]@{ Name = [string]$k; Value = $Value[$k] }
    }
  } else {
    foreach($p in ($Value.PSObject.Properties | Sort-Object Name)){
      if($p.MemberType -notin @('NoteProperty','Property','AliasProperty','ScriptProperty')){ continue }
      $props += [pscustomobject]@{ Name = [string]$p.Name; Value = $p.Value }
    }
  }

  $props = @($props | Sort-Object Name -Unique)
  foreach($p in $props){
    $k = ($p.Name | ConvertTo-Json -Compress)
    $v = (To-CanonJson $p.Value)
    [void]$pairs.Add($k + ':' + $v)
  }

  return ('{' + ($pairs.ToArray() -join ',') + '}')
}

function Utf8NoBomBytes([string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  return $enc.GetBytes($Text)
}

$RepoRoot   = (Resolve-Path -LiteralPath $RepoRoot).Path
$ArchiveDir = (Resolve-Path -LiteralPath $ArchiveDir).Path

if(-not (Test-Path -LiteralPath $ArchiveDir -PathType Container)){ Die ("ARCHIVE_DIR_NOT_FOUND: " + $ArchiveDir) }

$ManifestPath = Join-Path $ArchiveDir "manifest.triad.json"
$BlobsDir     = Join-Path $ArchiveDir "blobs"

if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){ Die ("MANIFEST_NOT_FOUND: " + $ManifestPath) }
if(-not (Test-Path -LiteralPath $BlobsDir -PathType Container)){ Die ("BLOBS_DIR_NOT_FOUND: " + $BlobsDir) }

$manifestObj = Read-Utf8 $ManifestPath | ConvertFrom-Json
if([string]$manifestObj.schema -ne "triad.archive.manifest.v1"){ Die "MANIFEST_SCHEMA_MISMATCH" }

$entries = @(@($manifestObj.entries))
if([int]$manifestObj.entry_count -ne $entries.Count){ Die "MANIFEST_ENTRY_COUNT_MISMATCH" }

$rootParts = New-Object System.Collections.Generic.List[string]
foreach($e in $entries){
  $path = [string]$e.path
  $sha  = [string]$e.sha256
  $size = [int64]$e.size
  $blobRef = [string]$e.blob_ref

  if([string]::IsNullOrWhiteSpace($path)){ Die "ENTRY_PATH_EMPTY" }
  if($path.StartsWith("/") -or $path -match '^[A-Za-z]:'){ Die ("ENTRY_ABSOLUTE_PATH_INVALID: " + $path) }
  if($path.Contains("../") -or $path.Contains("..\")){ Die ("ENTRY_TRAVERSAL_INVALID: " + $path) }

  $blobPath = Join-Path $ArchiveDir ($blobRef -replace '/','\')
  if(-not (Test-Path -LiteralPath $blobPath -PathType Leaf)){ Die ("BLOB_MISSING: " + $blobPath) }

  $actualSha = Sha256HexFile $blobPath
  if($actualSha -ne $sha){ Die ("BLOB_SHA_MISMATCH: " + $blobPath) }

  $actualSize = [int64](Get-Item -LiteralPath $blobPath).Length
  if($actualSize -ne $size){ Die ("BLOB_SIZE_MISMATCH: " + $blobPath) }

  [void]$rootParts.Add($path + "|" + $sha + "|" + $size)
}

$rootJoined = ($rootParts.ToArray() -join "`n")
$actualRootHash = Sha256HexBytes (Utf8NoBomBytes $rootJoined)
if($actualRootHash -ne [string]$manifestObj.root_hash){ Die "ROOT_HASH_MISMATCH" }

$idParts = New-Object System.Collections.Generic.List[string]
[void]$idParts.Add("triad.archive.manifest.v1")
[void]$idParts.Add([string]$manifestObj.root_hash)
[void]$idParts.Add(([string]$entries.Count))

foreach($e in (@(@($entries)) | Sort-Object path)){
  [void]$idParts.Add(([string]$e.path + "|" + [string]$e.sha256 + "|" + [string]$e.size + "|" + [string]$e.blob_ref))
}

$idJoined = ($idParts.ToArray() -join "`n")
$actualArchiveId = Sha256HexBytes (Utf8NoBomBytes $idJoined)
if($actualArchiveId -ne [string]$manifestObj.archive_id){
  Die ("ARCHIVE_ID_MISMATCH: got=" + $actualArchiveId + " expected=" + [string]$manifestObj.archive_id)
}

Write-Host ("ARCHIVE_DIR: " + $ArchiveDir) -ForegroundColor DarkGray
Write-Host ("ARCHIVE_ID: " + [string]$manifestObj.archive_id) -ForegroundColor Cyan
Write-Host ("ROOT_HASH: " + $actualRootHash) -ForegroundColor DarkGray
Write-Host ("ENTRY_COUNT: " + $entries.Count) -ForegroundColor DarkGray
Write-Host "TRIAD_ARCHIVE_VERIFY_V1_OK" -ForegroundColor Green
