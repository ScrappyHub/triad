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

function To-CanonJson([object]$Value){
  if($null -eq $Value){ return 'null' }

  if($Value -is [string]){
    return ($Value | ConvertTo-Json -Compress)
  }

  if(($Value -is [int]) -or ($Value -is [long]) -or ($Value -is [double]) -or ($Value -is [decimal]) -or ($Value -is [float])){
    return ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture,'{0}',$Value))
  }

  if($Value -is [bool]){
    if($Value){ return 'true' } else { return 'false' }
  }

  if(($Value -is [System.Collections.IEnumerable]) -and
     -not ($Value -is [string]) -and
     -not ($Value -is [System.Collections.IDictionary]) -and
     -not ($Value -is [psobject])){
    $parts = New-Object System.Collections.Generic.List[string]
    foreach($item in $Value){
      [void]$parts.Add((To-CanonJson $item))
    }
    return ('[' + ($parts.ToArray() -join ',') + ']')
  }

  $pairs = New-Object System.Collections.Generic.List[string]
  $props = @()

  if($Value -is [System.Collections.IDictionary]){
    foreach($k in $Value.Keys){
      $props += [pscustomobject]@{ Name = [string]$k; Value = $Value[$k] }
    }
  } else {
    foreach($p in ($Value.PSObject.Properties | Sort-Object Name)){
      if($p.MemberType -notin @('NoteProperty','Property','AliasProperty','ScriptProperty')){ continue }
      $props += [pscustomobject]@{ Name = [string]$p.Name; Value = $p.Value }
    }
  }

  $props = @($props | Sort-Object Name -Unique)
  foreach($p in $props){
    $k = ($p.Name | ConvertTo-Json -Compress)
    $v = (To-CanonJson $p.Value)
    [void]$pairs.Add($k + ':' + $v)
  }

  return ('{' + ($pairs.ToArray() -join ',') + '}')
}

function Append-Receipt([string]$Path,[object]$Receipt){
  $line = (To-CanonJson $Receipt)
  if(Test-Path -LiteralPath $Path -PathType Leaf){
    $prev = Read-Utf8 $Path
    Write-Utf8NoBomLf $Path ($prev + $line + "`n")
  } else {
    Write-Utf8NoBomLf $Path ($line + "`n")
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$FullGreenPath = Join-Path $ScriptsDir "_RUN_triad_full_green_v1.ps1"
if(-not (Test-Path -LiteralPath $FullGreenPath -PathType Leaf)){ Die ("MISSING_FULL_GREEN_RUNNER: " + $FullGreenPath) }

$FreezeRoot = Join-Path $RepoRoot "proofs\freeze"
$ReceiptPath = Join-Path $RepoRoot "proofs\receipts\triad.freeze.v1.ndjson"
Ensure-Dir $FreezeRoot
Ensure-Dir (Join-Path $RepoRoot "proofs\receipts")

$stamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$OutDir = Join-Path $FreezeRoot ("triad_engine_green_" + $stamp)
Ensure-Dir $OutDir

$TranscriptPath = Join-Path $OutDir "full_green_transcript.txt"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"
$psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$FullGreenPath`" -RepoRoot `"$RepoRoot`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
[void]$p.Start()
$stdout = $p.StandardOutput.ReadToEnd()
$stderr = $p.StandardError.ReadToEnd()
$p.WaitForExit()

$transcript = $stdout + "`n=== STDERR ===`n" + $stderr
Write-Utf8NoBomLf $TranscriptPath $transcript

if($p.ExitCode -ne 0){ Die ("FULL_GREEN_RUNNER_FAILED: " + $TranscriptPath) }
if($transcript -notmatch "TRIAD_FULL_GREEN_V1_OK"){ Die ("FULL_GREEN_TOKEN_MISSING: " + $TranscriptPath) }

$Artifacts = @(
  $TranscriptPath,
  $FullGreenPath,
  (Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"),
  (Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"),
  (Join-Path $ScriptsDir "triad_restore_commit_v1.ps1"),
  (Join-Path $ScriptsDir "triad_capture_tree_v1.ps1"),
  (Join-Path $ScriptsDir "triad_archive_pack_v1.ps1"),
  (Join-Path $ScriptsDir "triad_archive_verify_v1.ps1"),
  (Join-Path $ScriptsDir "triad_archive_extract_v1.ps1"),
  (Join-Path $ScriptsDir "triad_transform_apply_v1.ps1"),
  (Join-Path $ScriptsDir "triad_transform_verify_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_workflow_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_stress_seed_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_vector_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_negative_block_sha_corruption_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_negative_missing_block_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_negative_payload_sha_mismatch_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_negative_payload_length_mismatch_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_stress_deeper_tree_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_stress_multi_file_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_stress_repeated_blocks_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_stress_tail_partial_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_archive_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_archive_extract_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_archive_negative_tampered_blob_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_archive_negative_missing_blob_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_archive_negative_output_not_empty_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_archive_negative_path_traversal_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_transform_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_transform_negative_unknown_type_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_transform_negative_input_sha_mismatch_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_transform_negative_output_sha_mismatch_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_transform_negative_transform_id_mismatch_v1.ps1")
)

$Rows = New-Object System.Collections.Generic.List[string]
$ManifestRows = New-Object System.Collections.Generic.List[object]

foreach($a in $Artifacts){
  if(-not (Test-Path -LiteralPath $a -PathType Leaf)){ Die ("FREEZE_ARTIFACT_MISSING: " + $a) }
  $sha = Sha256HexFile $a
  $name = Split-Path -Leaf $a
  [void]$Rows.Add($sha + "  " + $name)
  [void]$ManifestRows.Add([pscustomobject]@{
    file_name = $name
    sha256    = $sha
  })
  Copy-Item -LiteralPath $a -Destination (Join-Path $OutDir $name) -Force
}

Write-Utf8NoBomLf (Join-Path $OutDir "sha256sums.txt") (($Rows.ToArray()) -join "`n")

$FreezeManifest = [ordered]@{
  schema         = "triad.freeze.manifest.v1"
  freeze_dir     = $OutDir
  transcript_sha = (Sha256HexFile $TranscriptPath)
  artifact_count = $ManifestRows.Count
  artifacts      = @($ManifestRows)
}
$FreezeManifestJson = To-CanonJson $FreezeManifest
Write-Utf8NoBomLf (Join-Path $OutDir "FREEZE_MANIFEST.v1.json") $FreezeManifestJson
$FreezeManifestSha = Sha256HexBytes (Utf8NoBomBytes $FreezeManifestJson)

Append-Receipt $ReceiptPath ([ordered]@{
  event               = "triad.freeze.v1"
  freeze_dir          = $OutDir
  freeze_manifest_sha = $FreezeManifestSha
  artifact_count      = $ManifestRows.Count
  status              = "OK"
})

Write-Host ("FREEZE_DIR: " + $OutDir) -ForegroundColor Cyan
Write-Host ("FREEZE_MANIFEST_SHA256: " + $FreezeManifestSha) -ForegroundColor DarkGray
Write-Host "TRIAD_FREEZE_V1_OK" -ForegroundColor Green
