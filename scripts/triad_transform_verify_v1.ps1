param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ManifestPath
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

function Utf8NoBomBytes([string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  return $enc.GetBytes($Text)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path

if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){ Die ("MANIFEST_NOT_FOUND: " + $ManifestPath) }

$m = Read-Utf8 $ManifestPath | ConvertFrom-Json
if([string]$m.schema -ne "triad.transform.manifest.v1"){ Die "TRANSFORM_SCHEMA_MISMATCH" }

$InputPath  = [string]$m.input_path
$OutputPath = [string]$m.output_path

if(-not (Test-Path -LiteralPath $InputPath -PathType Leaf)){ Die ("INPUT_NOT_FOUND: " + $InputPath) }
if(-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)){ Die ("OUTPUT_NOT_FOUND: " + $OutputPath) }

$inputSha = Sha256HexFile $InputPath
$outputSha = Sha256HexFile $OutputPath

if($inputSha -ne [string]$m.input_sha256){ Die "INPUT_SHA_MISMATCH" }
if($outputSha -ne [string]$m.output_sha256){ Die "OUTPUT_SHA_MISMATCH" }

$idParts = New-Object System.Collections.Generic.List[string]
[void]$idParts.Add("triad.transform.manifest.v1")
[void]$idParts.Add([string]$m.transform_type)
[void]$idParts.Add($inputSha)
[void]$idParts.Add($outputSha)
[void]$idParts.Add((Split-Path -Leaf $InputPath))
[void]$idParts.Add((Split-Path -Leaf $OutputPath))
$actualTransformId = Sha256HexBytes (Utf8NoBomBytes (($idParts.ToArray()) -join "`n"))

if($actualTransformId -ne [string]$m.transform_id){ Die "TRANSFORM_ID_MISMATCH" }

Write-Host ("TRANSFORM_ID: " + $actualTransformId) -ForegroundColor Cyan
Write-Host ("TRANSFORM_TYPE: " + [string]$m.transform_type) -ForegroundColor DarkGray
Write-Host "TRIAD_TRANSFORM_VERIFY_V1_OK" -ForegroundColor Green
