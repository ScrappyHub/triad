param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$Message){
  throw $Message
}

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

function PropOf($Object,[string]$Name){
  if($null -eq $Object){ return $null }
  $prop = $Object.PSObject.Properties[$Name]
  if($null -eq $prop){ return $null }
  return $prop.Value
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$FreezeRoot = Join-Path $RepoRoot "proofs\freeze"
$VectorRoot = Join-Path $RepoRoot "test_vectors\restore\v1\positive\locked_green_restore_vector"
$ScriptsDir = Join-Path $RepoRoot "scripts"

if(-not (Test-Path -LiteralPath $FreezeRoot -PathType Container)){ Die ("MISSING_FREEZE_ROOT: " + $FreezeRoot) }
if(-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)){ Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }

$Freeze = Get-ChildItem -LiteralPath $FreezeRoot -Directory |
  Where-Object { $_.Name -like "triad_restore_green_*" } |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1

if($null -eq $Freeze){ Die "NO_TRIAD_RESTORE_GREEN_FREEZE_FOUND" }

$FreezeDir = $Freeze.FullName
$FreezeSnapshot = Join-Path $FreezeDir "snapshot_v1"
$FreezeLedger = Join-Path $FreezeDir "FREEZE_LEDGER.md"
$FreezeTranscript = Join-Path $FreezeDir "selftest_transcript.txt"
$FreezeRestored = Join-Path $FreezeDir "restored.bin"

if(-not (Test-Path -LiteralPath $FreezeSnapshot -PathType Container)){ Die ("MISSING_FREEZE_SNAPSHOT: " + $FreezeSnapshot) }
if(-not (Test-Path -LiteralPath $FreezeLedger -PathType Leaf)){ Die ("MISSING_FREEZE_LEDGER: " + $FreezeLedger) }
if(-not (Test-Path -LiteralPath $FreezeTranscript -PathType Leaf)){ Die ("MISSING_FREEZE_TRANSCRIPT: " + $FreezeTranscript) }
if(-not (Test-Path -LiteralPath $FreezeRestored -PathType Leaf)){ Die ("MISSING_FREEZE_RESTORED_BIN: " + $FreezeRestored) }

$FreezePlanFiles = Get-ChildItem -LiteralPath $FreezeDir -File | Where-Object { $_.Name -like "*.triad_plan*.json" }
$ProductScripts = @("triad_restore_prepare_v1.ps1","triad_restore_verify_v1.ps1","triad_restore_commit_v1.ps1","_selftest_triad_restore_workflow_v1.ps1")
foreach($name in $ProductScripts){
  $src = Join-Path $ScriptsDir $name
  if(-not (Test-Path -LiteralPath $src -PathType Leaf)){ Die ("MISSING_PRODUCT_SCRIPT: " + $src) }
}

Ensure-Dir $VectorRoot
Get-ChildItem -LiteralPath $VectorRoot -Force -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }

$VectorPlans = Join-Path $VectorRoot "plans"
$VectorScripts = Join-Path $VectorRoot "scripts"
Ensure-Dir $VectorPlans
Ensure-Dir $VectorScripts
Copy-Item -LiteralPath $FreezeSnapshot -Destination $VectorRoot -Recurse -Force
$VectorSnapshot = Join-Path $VectorRoot "snapshot_v1"
if(-not (Test-Path -LiteralPath $VectorSnapshot -PathType Container)){ Die ("VECTOR_SNAPSHOT_COPY_FAILED: " + $VectorSnapshot) }

foreach($f in $FreezePlanFiles){ Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $VectorPlans $f.Name) -Force }
Copy-Item -LiteralPath $FreezeRestored -Destination (Join-Path $VectorRoot "restored.bin") -Force
Copy-Item -LiteralPath $FreezeLedger -Destination (Join-Path $VectorRoot "FREEZE_LEDGER.md") -Force
Copy-Item -LiteralPath $FreezeTranscript -Destination (Join-Path $VectorRoot "selftest_transcript.txt") -Force
foreach($name in $ProductScripts){ Copy-Item -LiteralPath (Join-Path $ScriptsDir $name) -Destination (Join-Path $VectorScripts $name) -Force }

$ManifestPath = Join-Path $VectorSnapshot "snapshot.tree.manifest.json"
if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){ Die ("MISSING_VECTOR_MANIFEST: " + $ManifestPath) }
$ManifestObj = Read-Utf8 $ManifestPath | ConvertFrom-Json
$Entries = @(@(PropOf $ManifestObj "entries"))
$PayloadEntry = $null
foreach($e in $Entries){
  if($null -eq $e){ continue }
  $type = [string](PropOf $e "type")
  $path = [string](PropOf $e "path")
  if($type -eq "file" -and $path -eq "payload.bin"){ $PayloadEntry = $e; break }
}
if($null -eq $PayloadEntry){ Die "VECTOR_PAYLOAD_ENTRY_NOT_FOUND" }
$PayloadRoots = PropOf $PayloadEntry "roots"
$PayloadBlocks = @(@(PropOf $PayloadEntry "blocks"))
if($null -eq $PayloadRoots){ Die "VECTOR_PAYLOAD_ROOTS_NOT_FOUND" }
if($PayloadBlocks.Count -lt 1){ Die "VECTOR_PAYLOAD_BLOCKS_NOT_FOUND" }

$RestoredPath = Join-Path $VectorRoot "restored.bin"
$SnapshotId = [string](PropOf $ManifestObj "snapshot_id")
$PayloadSha = [string](PropOf $PayloadEntry "sha256")
$PayloadLen = [int64](PropOf $PayloadEntry "length")
$PayloadRoot = [string](PropOf $PayloadRoots "block_root")
$BlockCount = $PayloadBlocks.Count
$RestoredSha = Sha256HexFile $RestoredPath

$Json = New-Object System.Collections.Generic.List[string]
[void]$Json.Add("{")
[void]$Json.Add('  "schema": "triad.restore.vector.v1",')
[void]$Json.Add('  "vector_id": "locked_green_restore_vector",')
[void]$Json.Add('  "snapshot_id": "' + $SnapshotId + '",')
[void]$Json.Add('  "payload_sha256": "' + $PayloadSha + '",')
[void]$Json.Add('  "payload_length": ' + $PayloadLen + ',')
[void]$Json.Add('  "payload_block_root": "' + $PayloadRoot + '",')
[void]$Json.Add('  "payload_block_count": ' + $BlockCount + ',')
[void]$Json.Add('  "restored_bin_sha256": "' + $RestoredSha + '",')
[void]$Json.Add('  "contract": {')
[void]$Json.Add('    "authoritative_source": "payload file entry in snapshot.tree.manifest.json",')
[void]$Json.Add('    "reconstruction_rule": "payloadEntry.blocks by index+offset+size",')
[void]$Json.Add('    "repeated_block_reuse_valid": true,')
[void]$Json.Add('    "naive_unique_blk_concatenation_valid": false')
[void]$Json.Add('  }')
[void]$Json.Add("}")
Write-Utf8NoBomLf (Join-Path $VectorRoot "vector_manifest.json") ($Json.ToArray() -join "`n")

$ReadmeLines = New-Object System.Collections.Generic.List[string]
[void]$ReadmeLines.Add("# TRIAD Restore Positive Vector")
[void]$ReadmeLines.Add("")
[void]$ReadmeLines.Add("Vector id: ``locked_green_restore_vector``")
[void]$ReadmeLines.Add("")
[void]$ReadmeLines.Add("This vector is seeded from the latest validated TRIAD green freeze.")
[void]$ReadmeLines.Add("")
[void]$ReadmeLines.Add("Locked facts:")
[void]$ReadmeLines.Add("")
[void]$ReadmeLines.Add("- snapshot_id: ``" + $SnapshotId + "``")
[void]$ReadmeLines.Add("- payload sha256: ``" + $PayloadSha + "``")
[void]$ReadmeLines.Add("- payload length: ``" + $PayloadLen + "``")
[void]$ReadmeLines.Add("- payload block root: ``" + $PayloadRoot + "``")
[void]$ReadmeLines.Add("- payload block count: ``" + $BlockCount + "``")
[void]$ReadmeLines.Add("")
[void]$ReadmeLines.Add("Restore contract:")
[void]$ReadmeLines.Add("")
[void]$ReadmeLines.Add("- payload file entry is authoritative")
[void]$ReadmeLines.Add("- payloadEntry.blocks is authoritative")
[void]$ReadmeLines.Add("- replay uses index + offset + size")
[void]$ReadmeLines.Add("- repeated block reuse is valid")
[void]$ReadmeLines.Add("- naive unique `.blk` concatenation is invalid")
Write-Utf8NoBomLf (Join-Path $VectorRoot "README.md") ($ReadmeLines.ToArray() -join "`n")

$HashRows = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $VectorRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
  $rel = $_.FullName.Substring($VectorRoot.Length).TrimStart("\")
  $rel = $rel.Replace("\","/")
  $hex = Sha256HexFile $_.FullName
  [void]$HashRows.Add($hex + "  " + $rel)
}
Write-Utf8NoBomLf (Join-Path $VectorRoot "sha256sums.txt") ($HashRows.ToArray() -join "`n")

Write-Host ("VECTOR_OK: " + $VectorRoot) -ForegroundColor Green
Write-Host ("VECTOR_SNAPSHOT_ID: " + $SnapshotId) -ForegroundColor Green
Write-Host ("VECTOR_PAYLOAD_SHA256: " + $PayloadSha) -ForegroundColor Green
Write-Host ("VECTOR_RESTORED_SHA256: " + $RestoredSha) -ForegroundColor Green
