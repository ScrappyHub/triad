param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$InputDir,
  [Parameter(Mandatory=$true)][string]$OutputManifest,
  [int]$BlockSize = 1048576
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

if(-not (Test-Path $InputDir -PathType Container)){ Die ("INPUT_DIR_NOT_FOUND: " + $InputDir) }
if(Test-Path $OutputManifest){ Die ("OUTPUT_ALREADY_EXISTS: " + $OutputManifest) }
if($BlockSize -le 0){ Die "INVALID_BLOCK_SIZE" }

$InputDir = (Resolve-Path $InputDir).Path

function Get-Sha256Hex([byte[]]$Bytes){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
  } finally {
    $sha.Dispose()
  }
  return ([System.BitConverter]::ToString($hash)).Replace("-","").ToLowerInvariant()
}

$allDirs = Get-ChildItem -LiteralPath $InputDir -Recurse -Directory -Force | Sort-Object FullName
$allFiles = Get-ChildItem -LiteralPath $InputDir -Recurse -File -Force | Sort-Object FullName

$dirEntries = New-Object System.Collections.Generic.List[object]
foreach($dir in $allDirs){
  $rel = $dir.FullName.Substring($InputDir.Length).TrimStart('\')
  $dirEntries.Add([pscustomobject]@{
    path = $rel
    last_write = $dir.LastWriteTimeUtc.ToString("o")
  }) | Out-Null
}

$blockStore = @{}
$fileEntries = New-Object System.Collections.Generic.List[object]
$rootParts = New-Object System.Collections.Generic.List[string]
[void]$rootParts.Add("triad.blockmap.dir.manifest.v1")
[void]$rootParts.Add([string]$BlockSize)

foreach($dir in $dirEntries){
  [void]$rootParts.Add(("dir|" + $dir.path + "|" + $dir.last_write))
}

foreach($file in $allFiles){
  $full = $file.FullName
  $rel = $full.Substring($InputDir.Length).TrimStart('\')

  $fs = [System.IO.File]::OpenRead($full)
  try {
    $buffer = New-Object byte[] $BlockSize
    $fileBlocks = New-Object System.Collections.Generic.List[object]
    $offset = [int64]0

    while($true){
      $read = $fs.Read($buffer, 0, $buffer.Length)
      if($read -le 0){ break }

      $chunk = New-Object byte[] $read
      [System.Array]::Copy($buffer, 0, $chunk, 0, $read)

      $sha = Get-Sha256Hex $chunk

      if(-not $blockStore.ContainsKey($sha)){
        $blockStore[$sha] = [pscustomobject]@{
          sha256 = $sha
          size = $read
          ref_count = 1
        }
      } else {
        $blockStore[$sha].ref_count = [int]$blockStore[$sha].ref_count + 1
      }

      $fileBlocks.Add([pscustomobject]@{
        index = $fileBlocks.Count
        offset = $offset
        size = $read
        sha256 = $sha
      }) | Out-Null

      [void]$rootParts.Add(($rel + "|" + [string]$offset + "|" + [string]$read + "|" + $sha))
      $offset += $read
    }

    $fileEntries.Add([pscustomobject]@{
      path = $rel
      size = $file.Length
      last_write = $file.LastWriteTimeUtc.ToString("o")
      block_count = $fileBlocks.Count
      blocks = $fileBlocks
    }) | Out-Null
  }
  finally {
    $fs.Dispose()
  }
}

$sortedBlockKeys = $blockStore.Keys | Sort-Object
foreach($k in $sortedBlockKeys){
  $b = $blockStore[$k]
  [void]$rootParts.Add(("block|" + $b.sha256 + "|" + [string]$b.size + "|" + [string]$b.ref_count))
}

$rootJoined = ($rootParts.ToArray() -join "`n")
$rootHash = Get-Sha256Hex ([System.Text.Encoding]::UTF8.GetBytes($rootJoined))

$sortedBlocks = New-Object System.Collections.Generic.List[object]
foreach($k in $sortedBlockKeys){
  $sortedBlocks.Add($blockStore[$k]) | Out-Null
}

$manifest = [pscustomobject]@{
  manifest_version = "triad.blockmap.dir.manifest.v1"
  input_dir = $InputDir
  block_size = $BlockSize
  dir_count = $dirEntries.Count
  file_count = $fileEntries.Count
  unique_block_count = $sortedBlocks.Count
  root_hash = $rootHash
  dirs = $dirEntries
  block_store = $sortedBlocks
  files = $fileEntries
}

$manifest | ConvertTo-Json -Depth 12 | Out-File -Encoding utf8 $OutputManifest

Write-Host ("ROOT_HASH: " + $rootHash)
Write-Host ("DIR_COUNT: " + $dirEntries.Count)
Write-Host ("FILE_COUNT: " + $fileEntries.Count)
Write-Host ("UNIQUE_BLOCK_COUNT: " + $sortedBlocks.Count)
Write-Host ("BLOCK_SIZE: " + $BlockSize)
Write-Host "TRIAD_BLOCKMAP_DIR_V1_OK"
