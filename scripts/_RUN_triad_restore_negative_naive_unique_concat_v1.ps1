param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Ensure-Dir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ Die "ENSURE_DIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
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
    try { $hash = $sha.ComputeHash($fs) } finally { $fs.Dispose() }
  } finally { $sha.Dispose() }
  return ([BitConverter]::ToString($hash)).Replace("-","").ToLowerInvariant()
}

# ---------------------------------------------------------
# Paths
# ---------------------------------------------------------

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$VectorRoot = Join-Path $RepoRoot "test_vectors\restore\v1\positive\locked_green_restore_vector"
$NegRoot    = Join-Path $RepoRoot "test_vectors\restore\v1\negative\naive_unique_concat_invalid_v1"

if(-not (Test-Path -LiteralPath $VectorRoot -PathType Container)){
  Die ("MISSING_POS_VECTOR: " + $VectorRoot)
}

Ensure-Dir $NegRoot

# clean
Get-ChildItem -LiteralPath $NegRoot -Force -ErrorAction SilentlyContinue | ForEach-Object {
  Remove-Item -LiteralPath $_.FullName -Recurse -Force
}

# ---------------------------------------------------------
# Load baseline
# ---------------------------------------------------------

$ManifestPath = Join-Path $VectorRoot "snapshot_v1\snapshot.tree.manifest.json"
$RestoredPath = Join-Path $VectorRoot "restored.bin"

$ManifestObj = Read-Utf8 $ManifestPath | ConvertFrom-Json
$Entries = @(@($ManifestObj.entries))

$PayloadEntry = $null
foreach($e in $Entries){
  if($null -eq $e){ continue }
  if([string]$e.type -eq "file" -and [string]$e.path -eq "payload.bin"){
    $PayloadEntry = $e
    break
  }
}

if($null -eq $PayloadEntry){ Die "PAYLOAD_ENTRY_NOT_FOUND" }

$ExpectedSha = [string]$PayloadEntry.sha256
$ExpectedLen = [int64]$PayloadEntry.length

# ---------------------------------------------------------
# NAIVE BUILD (INTENTIONALLY WRONG)
# ---------------------------------------------------------

$BlockDir = Join-Path $VectorRoot "snapshot_v1\blocks"
$NaiveOut = Join-Path $NegRoot "naive_output.bin"

$files = Get-ChildItem -LiteralPath $BlockDir -File | Sort-Object Name

$fs = [System.IO.File]::Create($NaiveOut)
foreach($f in $files){
  $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
  $fs.Write($bytes,0,$bytes.Length)
}
$fs.Close()

$NaiveSha = Sha256HexFile $NaiveOut
$NaiveLen = (Get-Item $NaiveOut).Length

# ---------------------------------------------------------
# Manifest (SAFE BUILD)
# ---------------------------------------------------------

$L = New-Object System.Collections.Generic.List[string]

[void]$L.Add("{")
[void]$L.Add('  "schema": "triad.restore.negative.vector.v1",')
[void]$L.Add('  "vector_id": "naive_unique_concat_invalid_v1",')
[void]$L.Add('  "expected_result": "FAIL",')
[void]$L.Add('  "expected_payload_sha256": "' + $ExpectedSha + '",')
[void]$L.Add('  "expected_payload_length": ' + $ExpectedLen + ',')
[void]$L.Add('  "naive_output_sha256": "' + $NaiveSha + '",')
[void]$L.Add('  "naive_output_length": ' + $NaiveLen)
[void]$L.Add("}")

Write-Utf8NoBomLf (Join-Path $NegRoot "negative_vector_manifest.json") (($L.ToArray()) -join "`n")

# ---------------------------------------------------------
# README
# ---------------------------------------------------------

$Readme = @(
  "# TRIAD Negative Vector - Naive Unique Concat Invalid",
  "",
  ("expected payload sha256: " + $ExpectedSha),
  ("naive output sha256: " + $NaiveSha),
  "",
  "Expected: FAIL"
) -join "`n"

Write-Utf8NoBomLf (Join-Path $NegRoot "README.md") $Readme

Write-Host ("NEG_VECTOR_OK: " + $NegRoot) -ForegroundColor Green