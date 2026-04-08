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

function Run-Child([string]$Script,[string]$RepoRoot){
  if(-not (Test-Path -LiteralPath $Script -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $Script) }

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Script`" -RepoRoot `"$RepoRoot`""
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

  return [pscustomobject]@{
    Script   = $Script
    ExitCode = $p.ExitCode
    StdOut   = $stdout
    StdErr   = $stderr
    Output   = $stdout + "`n" + $stderr
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$ProofRoot  = Join-Path $RepoRoot "proofs"
$FreezeRoot = Join-Path $ProofRoot "freeze"
$ReceiptDir = Join-Path $ProofRoot "receipts"
$RunStamp   = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$FreezeDir  = Join-Path $FreezeRoot ("triad_full_green_" + $RunStamp)

Ensure-Dir $FreezeRoot
Ensure-Dir $ReceiptDir
Ensure-Dir $FreezeDir

$Targets = @(
  (Join-Path $ScriptsDir "_selftest_triad_restore_workflow_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_vector_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_stress_seed_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_stress_deeper_tree_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_stress_multi_file_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_stress_repeated_blocks_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_stress_tail_partial_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_negative_block_sha_corruption_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_negative_missing_block_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_negative_payload_sha_mismatch_v1.ps1"),
  (Join-Path $ScriptsDir "_selftest_triad_restore_negative_payload_length_mismatch_v1.ps1"),
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

foreach($t in $Targets){
  if(-not (Test-Path -LiteralPath $t -PathType Leaf)){ Die ("MISSING_TARGET: " + $t) }
}

$TranscriptRows = New-Object System.Collections.Generic.List[string]
$ReceiptRows    = New-Object System.Collections.Generic.List[string]
$HashRows       = New-Object System.Collections.Generic.List[string]

foreach($t in $Targets){
  $r = Run-Child -Script $t -RepoRoot $RepoRoot

  $base = [System.IO.Path]::GetFileNameWithoutExtension($t)
  $outPath = Join-Path $FreezeDir ($base + ".stdout.txt")
  $errPath = Join-Path $FreezeDir ($base + ".stderr.txt")

  Write-Utf8NoBomLf $outPath $r.StdOut
  Write-Utf8NoBomLf $errPath $r.StdErr

  [void]$TranscriptRows.Add(("SCRIPT: " + $t))
  [void]$TranscriptRows.Add(("EXIT: " + [string]$r.ExitCode))
  [void]$TranscriptRows.Add(("STDOUT_SHA256: " + (Sha256HexFile $outPath)))
  [void]$TranscriptRows.Add(("STDERR_SHA256: " + (Sha256HexFile $errPath)))
  [void]$TranscriptRows.Add("")

  if($r.ExitCode -ne 0){
    Die ("SELFTEST_FAILED: " + $t + "`n" + $r.Output)
  }

  $receipt = [ordered]@{
    event       = "triad.full_green.child.v1"
    script      = $t
    exit_code   = $r.ExitCode
    stdout_sha  = (Sha256HexFile $outPath)
    stderr_sha  = (Sha256HexFile $errPath)
    status      = "OK"
  }
  [void]$ReceiptRows.Add(($receipt | ConvertTo-Json -Depth 20 -Compress))
}

$TranscriptPath = Join-Path $FreezeDir "full_green_transcript.txt"
Write-Utf8NoBomLf $TranscriptPath (($TranscriptRows.ToArray()) -join "`n")

Get-ChildItem -LiteralPath $FreezeDir -File | Sort-Object Name | ForEach-Object {
  $rel = $_.Name
  $hex = Sha256HexFile $_.FullName
  [void]$HashRows.Add($hex + "  " + $rel)
}

$ShaPath = Join-Path $FreezeDir "sha256sums.txt"
Write-Utf8NoBomLf $ShaPath (($HashRows.ToArray()) -join "`n")

$FreezeParts = New-Object System.Collections.Generic.List[string]
[void]$FreezeParts.Add("triad.full_green.freeze.v1")
[void]$FreezeParts.Add($RunStamp)

foreach($line in ($HashRows.ToArray())){
  [void]$FreezeParts.Add($line)
}

$FreezeId = Sha256HexBytes (Utf8NoBomBytes (($FreezeParts.ToArray()) -join "`n"))

$Manifest = [ordered]@{
  schema        = "triad.full_green.freeze.v1"
  freeze_id     = $FreezeId
  run_stamp_utc = $RunStamp
  repo_root     = $RepoRoot
  script_count  = $Targets.Count
  freeze_dir    = $FreezeDir
  transcript    = $TranscriptPath
  sha256sums    = $ShaPath
}
$ManifestPath = Join-Path $FreezeDir "freeze_manifest.json"
Write-Utf8NoBomLf $ManifestPath (($Manifest | ConvertTo-Json -Depth 20 -Compress))

$TopReceiptPath = Join-Path $ReceiptDir "triad.full_green.v1.ndjson"
$TopReceipt = [ordered]@{
  event        = "triad.full_green.freeze.v1"
  freeze_id    = $FreezeId
  freeze_dir   = $FreezeDir
  script_count = $Targets.Count
  status       = "OK"
}
$TopReceiptLine = ($TopReceipt | ConvertTo-Json -Depth 20 -Compress)

if(Test-Path -LiteralPath $TopReceiptPath -PathType Leaf){
  $prev = Read-Utf8 $TopReceiptPath
  Write-Utf8NoBomLf $TopReceiptPath ($prev + (($ReceiptRows.ToArray()) -join "`n") + "`n" + $TopReceiptLine + "`n")
} else {
  Write-Utf8NoBomLf $TopReceiptPath ((($ReceiptRows.ToArray()) -join "`n") + "`n" + $TopReceiptLine + "`n")
}

Write-Host ("FREEZE_DIR: " + $FreezeDir) -ForegroundColor DarkGray
Write-Host ("FREEZE_ID: " + $FreezeId) -ForegroundColor Cyan
Write-Host ("SCRIPT_COUNT: " + $Targets.Count) -ForegroundColor DarkGray
Write-Host "TRIAD_FULL_GREEN_AND_FREEZE_V1_OK" -ForegroundColor Green
