param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ArchiveDir,
  [Parameter(Mandatory=$true)][string]$OutputDir
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

$RepoRoot   = (Resolve-Path -LiteralPath $RepoRoot).Path
$ArchiveDir = (Resolve-Path -LiteralPath $ArchiveDir).Path

if(-not (Test-Path -LiteralPath $ArchiveDir -PathType Container)){ Die ("ARCHIVE_DIR_NOT_FOUND: " + $ArchiveDir) }

$ManifestPath = Join-Path $ArchiveDir "manifest.triad.json"
$BlobsDir     = Join-Path $ArchiveDir "blobs"

if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){ Die ("MANIFEST_NOT_FOUND: " + $ManifestPath) }
if(-not (Test-Path -LiteralPath $BlobsDir -PathType Container)){ Die ("BLOBS_DIR_NOT_FOUND: " + $BlobsDir) }

if(Test-Path -LiteralPath $OutputDir){
  $existing = Get-ChildItem -LiteralPath $OutputDir -Force -ErrorAction SilentlyContinue
  if(@(@($existing)).Count -gt 0){ Die ("OUTPUT_DIR_NOT_EMPTY: " + $OutputDir) }
} else {
  Ensure-Dir $OutputDir
}

$manifestObj = Read-Utf8 $ManifestPath | ConvertFrom-Json
if([string]$manifestObj.schema -ne "triad.archive.manifest.v1"){ Die "MANIFEST_SCHEMA_MISMATCH" }

$entries = @(@($manifestObj.entries))
if([int]$manifestObj.entry_count -ne $entries.Count){ Die "MANIFEST_ENTRY_COUNT_MISMATCH" }

$Extracted = New-Object System.Collections.Generic.List[string]

foreach($e in ($entries | Sort-Object path)){
  $path = [string]$e.path
  $sha  = [string]$e.sha256
  $size = [int64]$e.size
  $blobRef = [string]$e.blob_ref
  $type = [string]$e.type

  if($type -ne "file"){ Die ("UNSUPPORTED_ENTRY_TYPE: " + $type) }
  if([string]::IsNullOrWhiteSpace($path)){ Die "ENTRY_PATH_EMPTY" }
  if($path.StartsWith("/") -or $path -match '^[A-Za-z]:'){ Die ("ENTRY_ABSOLUTE_PATH_INVALID: " + $path) }
  if($path.Contains("../") -or $path.Contains("..\")){ Die ("ENTRY_TRAVERSAL_INVALID: " + $path) }

  $blobPath = Join-Path $ArchiveDir ($blobRef -replace '/','\')
  if(-not (Test-Path -LiteralPath $blobPath -PathType Leaf)){ Die ("BLOB_MISSING: " + $blobPath) }

  $blobSha = Sha256HexFile $blobPath
  if($blobSha -ne $sha){ Die ("BLOB_SHA_MISMATCH: " + $blobPath) }

  $blobLen = [int64](Get-Item -LiteralPath $blobPath).Length
  if($blobLen -ne $size){ Die ("BLOB_SIZE_MISMATCH: " + $blobPath) }

  $dest = Join-Path $OutputDir ($path -replace '/','\')
  $destDir = Split-Path -Parent $dest
  if($destDir){ Ensure-Dir $destDir }
  if(Test-Path -LiteralPath $dest -PathType Leaf){ Die ("DEST_ALREADY_EXISTS: " + $dest) }

  Copy-Item -LiteralPath $blobPath -Destination $dest -Force

  $destSha = Sha256HexFile $dest
  if($destSha -ne $sha){ Die ("EXTRACTED_SHA_MISMATCH: " + $dest) }

  $destLen = [int64](Get-Item -LiteralPath $dest).Length
  if($destLen -ne $size){ Die ("EXTRACTED_SIZE_MISMATCH: " + $dest) }

  [void]$Extracted.Add($path)
}

$ReceiptPath = Join-Path $RepoRoot "proofs\receipts\triad.archive.v1.ndjson"
$receipt = [ordered]@{
  event          = "triad.archive.extract.v1"
  archive_id     = [string]$manifestObj.archive_id
  archive_dir    = $ArchiveDir
  output_dir     = $OutputDir
  extracted_count = $Extracted.Count
  status         = "OK"
}
$receiptLine = ($receipt | ConvertTo-Json -Depth 20 -Compress)

if(Test-Path -LiteralPath $ReceiptPath -PathType Leaf){
  $prev = Read-Utf8 $ReceiptPath
  Write-Utf8NoBomLf $ReceiptPath ($prev + $receiptLine + "`n")
} else {
  Write-Utf8NoBomLf $ReceiptPath ($receiptLine + "`n")
}

Write-Host ("ARCHIVE_DIR: " + $ArchiveDir) -ForegroundColor DarkGray
Write-Host ("OUTPUT_DIR: " + $OutputDir) -ForegroundColor DarkGray
Write-Host ("EXTRACTED_COUNT: " + $Extracted.Count) -ForegroundColor DarkGray
Write-Host "TRIAD_ARCHIVE_EXTRACT_V1_OK" -ForegroundColor Green
