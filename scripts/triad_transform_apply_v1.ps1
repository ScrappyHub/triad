param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$TransformType,
  [Parameter(Mandatory=$true)][string]$InputPath,
  [Parameter(Mandatory=$true)][string]$OutputPath
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

function Apply-Transform([string]$Type,[string]$Text){
  switch($Type){
    "utf8_normalize_lf" {
      return $Text.Replace("`r`n","`n").Replace("`r","`n")
    }
    "trim_trailing_whitespace" {
      $norm = $Text.Replace("`r`n","`n").Replace("`r","`n")
      $lines = @($norm -split "`n",-1)
      for($i=0; $i -lt $lines.Count; $i++){
        $lines[$i] = [regex]::Replace($lines[$i],'[ \t]+$','')
      }
      return ($lines -join "`n")
    }
    default {
      Die ("UNKNOWN_TRANSFORM_TYPE: " + $Type)
    }
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$InputPath = (Resolve-Path -LiteralPath $InputPath).Path

if(-not (Test-Path -LiteralPath $InputPath -PathType Leaf)){ Die ("INPUT_NOT_FOUND: " + $InputPath) }
if(Test-Path -LiteralPath $OutputPath -PathType Leaf){ Die ("OUTPUT_ALREADY_EXISTS: " + $OutputPath) }

$inputText = Read-Utf8 $InputPath
$inputSha = Sha256HexFile $InputPath

$outputText = Apply-Transform $TransformType $inputText
Write-Utf8NoBomLf $OutputPath $outputText
$outputSha = Sha256HexFile $OutputPath

$idParts = New-Object System.Collections.Generic.List[string]
[void]$idParts.Add("triad.transform.manifest.v1")
[void]$idParts.Add($TransformType)
[void]$idParts.Add($inputSha)
[void]$idParts.Add($outputSha)
[void]$idParts.Add((Split-Path -Leaf $InputPath))
[void]$idParts.Add((Split-Path -Leaf $OutputPath))
$transformId = Sha256HexBytes (Utf8NoBomBytes (($idParts.ToArray()) -join "`n"))

$manifest = [ordered]@{
  schema          = "triad.transform.manifest.v1"
  transform_id    = $transformId
  transform_type  = $TransformType
  input_path      = $InputPath
  output_path     = $OutputPath
  input_sha256    = $inputSha
  output_sha256   = $outputSha
}
$ManifestPath = $OutputPath + ".transform_manifest.json"
Write-Utf8NoBomLf $ManifestPath (($manifest | ConvertTo-Json -Depth 20 -Compress))

$ReceiptPath = Join-Path $RepoRoot "proofs\receipts\triad.transform.v1.ndjson"
$receipt = [ordered]@{
  event          = "triad.transform.apply.v1"
  transform_id   = $transformId
  transform_type = $TransformType
  input_sha256   = $inputSha
  output_sha256  = $outputSha
  status         = "OK"
}
$receiptLine = ($receipt | ConvertTo-Json -Depth 20 -Compress)
if(Test-Path -LiteralPath $ReceiptPath -PathType Leaf){
  $prev = Read-Utf8 $ReceiptPath
  Write-Utf8NoBomLf $ReceiptPath ($prev + $receiptLine + "`n")
} else {
  Write-Utf8NoBomLf $ReceiptPath ($receiptLine + "`n")
}

Write-Host ("TRANSFORM_ID: " + $transformId) -ForegroundColor Cyan
Write-Host ("INPUT_SHA256: " + $inputSha) -ForegroundColor DarkGray
Write-Host ("OUTPUT_SHA256: " + $outputSha) -ForegroundColor DarkGray
Write-Host "TRIAD_TRANSFORM_APPLY_V1_OK" -ForegroundColor Green
