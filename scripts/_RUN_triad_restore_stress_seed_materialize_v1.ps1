param([Parameter(Mandatory=$true)][string]$RepoRoot)
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
    try { $hash = $sha.ComputeHash($fs) } finally { $fs.Dispose() }
  } finally { $sha.Dispose() }
  return ([BitConverter]::ToString($hash)).Replace("-","").ToLowerInvariant()
}

$VectorRoot = Join-Path $RepoRoot "test_vectors\restore\v1\positive\locked_green_restore_vector"
$StressRoot = Join-Path $RepoRoot "test_vectors\restore\v1\stress_seed_v1"
if(-not (Test-Path -LiteralPath $VectorRoot -PathType Container)){ Die ("MISSING_VECTOR_ROOT: " + $VectorRoot) }

$VectorSnapshot = Join-Path $VectorRoot "snapshot_v1"
$VectorScripts  = Join-Path $VectorRoot "scripts"
$VectorPlans    = Join-Path $VectorRoot "plans"
$VectorManifestPath = Join-Path $VectorSnapshot "snapshot.tree.manifest.json"
$VectorManifest2    = Join-Path $VectorRoot "vector_manifest.json"
$VectorRestoredPath = Join-Path $VectorRoot "restored.bin"
foreach($p in @($VectorSnapshot,$VectorScripts,$VectorPlans)){
  if(-not (Test-Path -LiteralPath $p -PathType Container)){ Die ("MISSING_VECTOR_DIR: " + $p) }
}
foreach($p in @($VectorManifestPath,$VectorManifest2,$VectorRestoredPath)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_VECTOR_FILE: " + $p) }
}

Ensure-Dir $StressRoot
Get-ChildItem -LiteralPath $StressRoot -Force -ErrorAction SilentlyContinue | ForEach-Object {
  Remove-Item -LiteralPath $_.FullName -Recurse -Force
}

$StressSnapshot = Join-Path $StressRoot "snapshot_v1"
$StressScripts  = Join-Path $StressRoot "scripts"
$StressPlans    = Join-Path $StressRoot "plans"
Ensure-Dir $StressSnapshot
Ensure-Dir $StressScripts
Ensure-Dir $StressPlans

Copy-Item -LiteralPath $VectorSnapshot -Destination $StressSnapshot -Recurse -Force
Get-ChildItem -LiteralPath $VectorPlans -File | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $StressPlans $_.Name) -Force
}
Get-ChildItem -LiteralPath $VectorScripts -File | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $StressScripts $_.Name) -Force
}
Copy-Item -LiteralPath $VectorManifestPath -Destination (Join-Path $StressRoot "snapshot.tree.manifest.json") -Force
Copy-Item -LiteralPath $VectorManifest2 -Destination (Join-Path $StressRoot "vector_manifest.json") -Force
Copy-Item -LiteralPath $VectorRestoredPath -Destination (Join-Path $StressRoot "restored.bin") -Force

$manifestObj = Read-Utf8 $VectorManifestPath | ConvertFrom-Json
$entries = @(@($manifestObj.entries))
$payloadEntry = $null
foreach($e in $entries){
  if($null -eq $e){ continue }
  $type = ""
  $path = ""
  try { $type = [string]$e.type } catch { $type = "" }
  try { $path = [string]$e.path } catch { $path = "" }
  if($type -eq "file" -and $path -eq "payload.bin"){ $payloadEntry = $e; break }
}
if($null -eq $payloadEntry){ Die "PAYLOAD_ENTRY_NOT_FOUND_STRESS_SEED_V1" }

$SnapshotId        = [string]$manifestObj.snapshot_id
$PayloadSha        = [string]$payloadEntry.sha256
$PayloadLen        = [int64]$payloadEntry.length
$PayloadRoot       = [string]$payloadEntry.roots.block_root
$PayloadBlockCount = @(@($payloadEntry.blocks)).Count
$RestoredSha       = Sha256HexFile $VectorRestoredPath

$SeedManifest = New-Object System.Collections.Generic.List[string]
[void]$SeedManifest.Add("{")
[void]$SeedManifest.Add('  "schema": "triad.restore.stress.seed.v1",')
[void]$SeedManifest.Add('  "seed_id": "stress_seed_v1",')
[void]$SeedManifest.Add(('  "snapshot_id": "' + $SnapshotId + '",') )
[void]$SeedManifest.Add(('  "payload_sha256": "' + $PayloadSha + '",') )
[void]$SeedManifest.Add(('  "payload_length": ' + $PayloadLen + ',') )
[void]$SeedManifest.Add(('  "payload_block_root": "' + $PayloadRoot + '",') )
[void]$SeedManifest.Add(('  "payload_block_count": ' + $PayloadBlockCount + ',') )
[void]$SeedManifest.Add(('  "restored_sha256": "' + $RestoredSha + '",') )
[void]$SeedManifest.Add('  "contract": {')
[void]$SeedManifest.Add('    "authoritative_source": "payload file entry in snapshot.tree.manifest.json",')
[void]$SeedManifest.Add('    "reconstruction_rule": "payloadEntry.blocks by index+offset+size",')
[void]$SeedManifest.Add('    "repeated_block_reuse_valid": true,')
[void]$SeedManifest.Add('    "naive_unique_blk_concatenation_valid": false')
[void]$SeedManifest.Add('  }')
[void]$SeedManifest.Add("}")
Write-Utf8NoBomLf (Join-Path $StressRoot "stress_seed_manifest.json") (($SeedManifest.ToArray()) -join "`n")

$Cases = @(
  "01_locked_green_baseline|positive|PASS|Locked positive baseline from validated green freeze."
  "02_repeated_block_reuse_contract|positive|PASS|Repeated block reuse remains valid because replay uses payloadEntry.blocks index+offset+size."
  "03_tail_partial_block_contract|positive|PASS|Tail partial block remains valid when final block size is smaller than chunk size."
  "04_naive_unique_concat_invalid|negative|FAIL|Naive concatenation of unique .blk files is invalid."
  "05_block_sha_corruption_negative|negative|FAIL|Corrupted block bytes must fail block hash validation."
  "06_payload_sha_mismatch_negative|negative|FAIL|Payload/output sha mismatch must fail verify."
  "07_missing_block_file_negative|negative|FAIL|Missing referenced block file must fail verify."
  "08_deeper_tree_seed|todo|TODO|Reserved seed for deeper tree structure vector."
  "09_multi_file_seed|todo|TODO|Reserved seed for multi-file restore vector."
)
Write-Utf8NoBomLf (Join-Path $StressRoot "stress_case_matrix.txt") ($Cases -join "`n")

$Readme = @'
# TRIAD Restore Stress Seed v1

This directory seeds the first restore stress harness from the validated TRIAD green baseline.

Locked baseline:

- snapshot_id: `__SNAPSHOT_ID__`
- payload sha256: `__PAYLOAD_SHA__`
- payload length: `__PAYLOAD_LEN__`
- payload block root: `__PAYLOAD_ROOT__`
- payload block count: `__PAYLOAD_BLOCK_COUNT__`
- restored sha256: `__RESTORED_SHA__`

Locked contract:

- payload file entry inside `snapshot.tree.manifest.json` is authoritative
- payloadEntry.blocks is authoritative for reconstruction
- replay uses index + offset + size
- repeated block reuse is valid
- naive unique `.blk` concatenation is invalid

Initial stress order:

1. locked green baseline
2. repeated block reuse
3. tail partial block
4. naive unique block concat negative
5. block sha corruption negative
6. payload sha mismatch negative
7. missing block file negative
8. deeper tree seed
9. multi-file seed
'@
$Readme = $Readme.Replace("__SNAPSHOT_ID__",$SnapshotId)
$Readme = $Readme.Replace("__PAYLOAD_SHA__",$PayloadSha)
$Readme = $Readme.Replace("__PAYLOAD_LEN__",([string]$PayloadLen))
$Readme = $Readme.Replace("__PAYLOAD_ROOT__",$PayloadRoot)
$Readme = $Readme.Replace("__PAYLOAD_BLOCK_COUNT__",([string]$PayloadBlockCount))
$Readme = $Readme.Replace("__RESTORED_SHA__",$RestoredSha)
Write-Utf8NoBomLf (Join-Path $StressRoot "README.md") $Readme

$HashRows = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $StressRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
  $rel = $_.FullName.Substring($StressRoot.Length).TrimStart("\").Replace("\","/")
  $hex = Sha256HexFile $_.FullName
  [void]$HashRows.Add($hex + "  " + $rel)
}
Write-Utf8NoBomLf (Join-Path $StressRoot "sha256sums.txt") (($HashRows.ToArray()) -join "`n")
Write-Host ("STRESS_SEED_OK: " + $StressRoot) -ForegroundColor Green
