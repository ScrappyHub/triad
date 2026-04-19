param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$InputFile,
  [Parameter(Mandatory=$true)][string]$BlockmapManifest,
  [Parameter(Mandatory=$true)][string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

if(-not (Test-Path $InputFile)){ Die ("INPUT_FILE_NOT_FOUND: " + $InputFile) }
if(-not (Test-Path $BlockmapManifest)){ Die ("BLOCKMAP_NOT_FOUND: " + $BlockmapManifest) }
if(Test-Path $OutputFile){ Die ("OUTPUT_ALREADY_EXISTS: " + $OutputFile) }

function Get-Sha256Hex([byte[]]$Bytes){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
  } finally {
    $sha.Dispose()
  }
  return ([System.BitConverter]::ToString($hash)).Replace("-","").ToLowerInvariant()
}

$manifest = Get-Content $BlockmapManifest -Raw | ConvertFrom-Json

$inFs = [System.IO.File]::OpenRead($InputFile)
$outFs = [System.IO.File]::Create($OutputFile)

try {
  foreach($b in $manifest.blocks){
    $inFs.Seek($b.offset, "Begin") | Out-Null

    $buffer = New-Object byte[] $b.size
    $read = $inFs.Read($buffer, 0, $buffer.Length)

    if($read -ne $b.size){
      Die "BLOCK_READ_MISMATCH"
    }

    $sha = Get-Sha256Hex $buffer
    if($sha -ne $b.sha256){
      Die ("BLOCK_HASH_MISMATCH: " + $b.index)
    }

    $outFs.Write($buffer, 0, $buffer.Length)
  }
}
finally {
  $inFs.Dispose()
  $outFs.Dispose()
}

# final file hash
$finalBytes = [System.IO.File]::ReadAllBytes($OutputFile)
$finalHash = Get-Sha256Hex $finalBytes

Write-Host ("RESTORED_FILE_HASH: " + $finalHash)
Write-Host "TRIAD_RESTORE_FROM_BLOCKMAP_V1_OK"
