param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$InputDir = ".\scripts\_work\triad_archive_selftest_v1\input"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

function Ensure-Dir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ Die "ENSURE_DIR_EMPTY" }
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

function Get-Sha256HexFile([string]$Path){
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$RepoRoot = (Resolve-Path $RepoRoot).Path
$Scripts = Join-Path $RepoRoot "scripts"

$FreezeRoot = Join-Path $RepoRoot "proofs\freeze"
$ReceiptsRoot = Join-Path $RepoRoot "proofs\receipts"
Ensure-Dir $FreezeRoot
Ensure-Dir $ReceiptsRoot

$RunId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmssZ")
$OutDir = Join-Path $FreezeRoot ("triad_dir_release_green_" + $RunId)
Ensure-Dir $OutDir

$Transcript = New-Object System.Collections.Generic.List[string]
function Add-Transcript([string]$Text){
  [void]$Transcript.Add($Text)
}

function Invoke-InProc([string]$Script,[hashtable]$Params,[string]$Section,[string]$SuccessToken){
  if(-not (Test-Path -LiteralPath $Script -PathType Leaf)){ Die ("SCRIPT_NOT_FOUND: " + $Script) }

  Add-Transcript ("=== " + $Section + " ===")
  & $Script @Params
  Add-Transcript $SuccessToken
}

Invoke-InProc (Join-Path $Scripts "_RUN_triad_dir_full_green_v1.ps1") @{
  RepoRoot = $RepoRoot
  InputDir = $InputDir
} "POSITIVE" "TRIAD_DIR_FULL_GREEN"

Invoke-InProc (Join-Path $Scripts "_selftest_triad_dir_negative_missing_block_v1.ps1") @{
  RepoRoot = $RepoRoot
} "NEGATIVE_MISSING_BLOCK" "TRIAD_DIR_NEGATIVE_MISSING_BLOCK_V1_OK"

Invoke-InProc (Join-Path $Scripts "_selftest_triad_dir_negative_tampered_block_v1.ps1") @{
  RepoRoot = $RepoRoot
} "NEGATIVE_TAMPERED_BLOCK" "TRIAD_DIR_NEGATIVE_TAMPERED_BLOCK_V1_OK"

Invoke-InProc (Join-Path $Scripts "_selftest_triad_dir_negative_tampered_manifest_v1.ps1") @{
  RepoRoot = $RepoRoot
} "NEGATIVE_TAMPERED_MANIFEST" "TRIAD_DIR_NEGATIVE_TAMPERED_MANIFEST_V1_OK"

$TranscriptPath = Join-Path $OutDir "dir_release_transcript.txt"
Write-Utf8NoBomLf $TranscriptPath (($Transcript.ToArray()) -join "`n")

$PosWorkRoot = Join-Path $RepoRoot "scripts\_work\triad_dir_full_green_v1"
if(Test-Path -LiteralPath $PosWorkRoot -PathType Container){
  Copy-Item -LiteralPath $PosWorkRoot -Destination (Join-Path $OutDir "triad_dir_full_green_work") -Recurse -Force
}

$ReceiptPath = Join-Path $OutDir "triad.dir.release.receipt.json"
$ReceiptObj = [pscustomobject]@{
  schema = "triad.dir.release.green.v1"
  utc = (Get-Date).ToUniversalTime().ToString("o")
  result = "TRIAD_DIR_RELEASE_GREEN"
  transcript = "dir_release_transcript.txt"
}
Write-Utf8NoBomLf $ReceiptPath ($ReceiptObj | ConvertTo-Json -Depth 6)

$Files = Get-ChildItem -LiteralPath $OutDir -Recurse -File | Sort-Object FullName
$Lines = New-Object System.Collections.Generic.List[string]
foreach($f in $Files){
  $rel = $f.FullName.Substring($OutDir.Length).TrimStart('\')
  [void]$Lines.Add((Get-Sha256HexFile $f.FullName) + "  " + $rel)
}
$ShaPath = Join-Path $OutDir "sha256sums.txt"
Write-Utf8NoBomLf $ShaPath (($Lines.ToArray()) -join "`n")

$NdjsonPath = Join-Path $ReceiptsRoot "triad.ndjson"
$NdjsonObj = [pscustomobject]@{
  schema = "triad.dir.release.green.v1"
  utc = (Get-Date).ToUniversalTime().ToString("o")
  result = "TRIAD_DIR_RELEASE_GREEN"
  freeze_dir = $OutDir
}
$Line = ($NdjsonObj | ConvertTo-Json -Compress)
if(Test-Path -LiteralPath $NdjsonPath){
  Add-Content -LiteralPath $NdjsonPath -Value $Line -Encoding utf8
} else {
  Write-Utf8NoBomLf $NdjsonPath $Line
}

Write-Host ("FREEZE_DIR: " + $OutDir)
Write-Host ("TRANSCRIPT_OK: " + $TranscriptPath)
Write-Host ("SHA256SUMS_OK: " + $ShaPath)
Write-Host ("RECEIPT_OK: " + $ReceiptPath)
Write-Host ("NDJSON_OK: " + $NdjsonPath)
Write-Host "TRIAD_DIR_RELEASE_GREEN"
