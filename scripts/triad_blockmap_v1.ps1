param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$InputPath,
  [Parameter(Mandatory=$true)][string]$OutputManifest,
  [int]$BlockSize = 1048576
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

if(-not (Test-Path $InputPath -PathType Leaf)){ Die ("INPUT_FILE_NOT_FOUND: " + $InputPath) }
if(Test-Path $OutputManifest){ Die ("OUTPUT_ALREADY_EXISTS: " + $OutputManifest) }
if($BlockSize -le 0){ Die "INVALID_BLOCK_SIZE" }

$InputPath = (Resolve-Path $InputPath).Path

function Get-Sha256Hex([byte[]]$Bytes){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
  } finally {
    $sha.Dispose()
  }
  return ([System.BitConverter]::ToString($hash)).Replace("-","").ToLowerInvariant()
}

$fs = [System.IO.File]::OpenRead($InputPath)
try {
  $fileLen = $fs.Length
  $buffer = New-Object byte[] $BlockSize
  $blocks = New-Object System.Collections.Generic.List[object]
  $blockHashes = New-Object System.Collections.Generic.List[string]

  $offset = [int64]0
  while($true){
    $read = $fs.Read($buffer, 0, $buffer.Length)
    if($read -le 0){ break }

    $chunk = New-Object byte[] $read
    [System.Array]::Copy($buffer, 0, $chunk, 0, $read)

    $sha = Get-Sha256Hex $chunk
    [void]$blockHashes.Add($sha)

    $blocks.Add([pscustomobject]@{
      index = $blocks.Count
      offset = $offset
      size = $read
      sha256 = $sha
    }) | Out-Null

    $offset += $read
  }
}
finally {
  $fs.Dispose()
}

$rootInput = @("triad.blockmap.manifest.v1", [string]$fileLen, [string]$BlockSize) + $blockHashes.ToArray()
$rootJoined = ($rootInput -join "`n")
$rootHash = Get-Sha256Hex ([System.Text.Encoding]::UTF8.GetBytes($rootJoined))

$manifest = [pscustomobject]@{
  manifest_version = "triad.blockmap.manifest.v1"
  input_path = $InputPath
  file_size = $fileLen
  block_size = $BlockSize
  block_count = $blocks.Count
  root_hash = $rootHash
  blocks = $blocks
}

$manifest | ConvertTo-Json -Depth 8 | Out-File -Encoding utf8 $OutputManifest

Write-Host ("ROOT_HASH: " + $rootHash)
Write-Host ("FILE_SIZE: " + $fileLen)
Write-Host ("BLOCK_SIZE: " + $BlockSize)
Write-Host ("BLOCK_COUNT: " + $blocks.Count)
Write-Host "TRIAD_BLOCKMAP_V1_OK"
