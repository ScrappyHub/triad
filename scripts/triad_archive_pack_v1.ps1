param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$InputDir,
  [Parameter(Mandatory=$true)][string]$ArchiveDir
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Ensure-Dir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ throw "ENSURE_DIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ Ensure-Dir $dir }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

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

function Utf8NoBomBytes([string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  return $enc.GetBytes($Text)
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

  if(($Value -is [System.Collections.IEnumerable]) -and
     -not ($Value -is [string]) -and
     -not ($Value -is [System.Collections.IDictionary]) -and
     -not ($Value -is [psobject])){
    $parts = New-Object System.Collections.Generic.List[string]
    foreach($item in $Value){
      [void]$parts.Add((To-CanonJson $item))
    }
    return ('[' + ($parts.ToArray() -join ',') + ']')
  }

  $pairs = New-Object System.Collections.Generic.List[string]
  $props = @()

  foreach($p in ($Value.PSObject.Properties | Sort-Object Name)){
    if($p.MemberType -notin @('NoteProperty','Property','AliasProperty','ScriptProperty')){ continue }
    $props += [pscustomobject]@{
      Name  = [string]$p.Name
      Value = $p.Value
    }
  }

  foreach($p in $props){
    $k = ($p.Name | ConvertTo-Json -Compress)
    $v = (To-CanonJson $p.Value)
    [void]$pairs.Add($k + ':' + $v)
  }

  return ('{' + ($pairs.ToArray() -join ',') + '}')
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$InputDir = (Resolve-Path -LiteralPath $InputDir).Path

if(-not (Test-Path -LiteralPath $InputDir -PathType Container)){ Die ("INPUT_DIR_NOT_FOUND: " + $InputDir) }

if(Test-Path -LiteralPath $ArchiveDir){
  $existing = Get-ChildItem -LiteralPath $ArchiveDir -Force -ErrorAction SilentlyContinue
  if(@(@($existing)).Count -gt 0){ Die ("ARCHIVE_DIR_NOT_EMPTY: " + $ArchiveDir) }
} else {
  Ensure-Dir $ArchiveDir
}

$BlobsDir = Join-Path $ArchiveDir "blobs"
Ensure-Dir $BlobsDir

$files = Get-ChildItem -LiteralPath $InputDir -Recurse -File | Sort-Object FullName
$entries = @()
$rootParts = New-Object System.Collections.Generic.List[string]

foreach($f in $files){
  $full = $f.FullName
  $rel  = $full.Substring($InputDir.Length).TrimStart('\').Replace('\','/')
  if([string]::IsNullOrWhiteSpace($rel)){ Die "EMPTY_REL_PATH" }
  if($rel.Contains("../") -or $rel.Contains("..\")){ Die ("PATH_TRAVERSAL_INPUT: " + $rel) }

  $sha  = Sha256HexFile $full
  $size = [int64]$f.Length
  $blobPath = Join-Path $BlobsDir $sha

  if(-not (Test-Path -LiteralPath $blobPath -PathType Leaf)){
    Copy-Item -LiteralPath $full -Destination $blobPath -Force
  }

  $entry = [ordered]@{
    path     = $rel
    type     = "file"
    size     = $size
    sha256   = $sha
    blob_ref = ("blobs/" + $sha)
  }

  $entries += [pscustomobject]$entry
  [void]$rootParts.Add($rel + "|" + $sha + "|" + $size)
}

$rootJoined = ($rootParts.ToArray() -join "`n")
$rootHash = Sha256HexBytes (Utf8NoBomBytes $rootJoined)

$manifestNoId = [ordered]@{
  schema      = "triad.archive.manifest.v1"
  root_hash   = $rootHash
  entry_count = @(@($entries)).Count
  entries     = @($entries)
}

$idParts = New-Object System.Collections.Generic.List[string]
[void]$idParts.Add("triad.archive.manifest.v1")
[void]$idParts.Add($rootHash)
[void]$idParts.Add(([string](@(@($entries)).Count)))

foreach($e in (@(@($entries)) | Sort-Object path)){
  [void]$idParts.Add(([string]$e.path + "|" + [string]$e.sha256 + "|" + [string]$e.size + "|" + [string]$e.blob_ref))
}

$idJoined = ($idParts.ToArray() -join "`n")
$archiveId = Sha256HexBytes (Utf8NoBomBytes $idJoined)

$manifest = [ordered]@{
  schema      = "triad.archive.manifest.v1"
  archive_id  = $archiveId
  root_hash   = $rootHash
  entry_count = @(@($entries)).Count
  entries     = @($entries)
}

$manifestPath = Join-Path $ArchiveDir "manifest.triad.json"
Write-Utf8NoBomLf $manifestPath (($manifest | ConvertTo-Json -Depth 100 -Compress))

$ReceiptPath = Join-Path $RepoRoot "proofs\receipts\triad.archive.v1.ndjson"
$receipt = [ordered]@{
  event         = "triad.archive.pack.v1"
  archive_id    = $archiveId
  archive_dir   = $ArchiveDir
  manifest_path = $manifestPath
  root_hash     = $rootHash
  entry_count   = @(@($entries)).Count
  status        = "OK"
}
$receiptLine = ($receipt | ConvertTo-Json -Depth 20 -Compress)

if(Test-Path -LiteralPath $ReceiptPath -PathType Leaf){
  $prev = Read-Utf8 $ReceiptPath
  Write-Utf8NoBomLf $ReceiptPath ($prev + $receiptLine + "`n")
} else {
  Write-Utf8NoBomLf $ReceiptPath ($receiptLine + "`n")
}

Write-Host ("ARCHIVE_DIR: " + $ArchiveDir) -ForegroundColor DarkGray
Write-Host ("ARCHIVE_ID: " + $archiveId) -ForegroundColor Cyan
Write-Host ("ROOT_HASH: " + $rootHash) -ForegroundColor DarkGray
Write-Host ("ENTRY_COUNT: " + @(@($entries)).Count) -ForegroundColor DarkGray
Write-Host "TRIAD_ARCHIVE_PACK_V1_OK" -ForegroundColor Green
