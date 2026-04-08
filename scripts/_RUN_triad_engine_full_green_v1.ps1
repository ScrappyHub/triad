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

function Parse-GateFile([string]$Path){
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  $errs = @()
  if($err -ne $null){ $errs = @(@($err)) }
  if($errs.Count -gt 0){
    $msg = ($errs | Select-Object -First 12 | ForEach-Object { $_.Message }) -join " | "
    throw ("PARSE_GATE_FAIL: " + $msg)
  }
}

function Run-Child([string]$Script,[string]$Arguments){
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Script`" " + $Arguments
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

  $txt = $stdout + "`n" + $stderr
  $txt = $txt.Replace("`r`n","`n").Replace("`r","`n")

  return [pscustomobject]@{
    ExitCode = $p.ExitCode
    Output   = $txt
  }
}

$RepoRoot   = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"
$FreezeRoot = Join-Path $RepoRoot "proofs\freeze"
$ReceiptPath = Join-Path $RepoRoot "proofs\receipts\triad.engine.full_green.v1.ndjson"

Ensure-Dir $FreezeRoot
Ensure-Dir (Split-Path -Parent $ReceiptPath)

$Stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$FreezeDir = Join-Path $FreezeRoot ("triad_engine_full_green_" + $Stamp)
Ensure-Dir $FreezeDir

$ScriptList = @(
  "triad_restore_prepare_v1.ps1",
  "triad_restore_verify_v1.ps1",
  "triad_restore_commit_v1.ps1",
  "_selftest_triad_restore_workflow_v1.ps1",
  "_selftest_triad_restore_vector_v1.ps1",
  "_selftest_triad_restore_negative_block_sha_corruption_v1.ps1",
  "_selftest_triad_restore_negative_missing_block_v1.ps1",
  "_selftest_triad_restore_negative_payload_sha_mismatch_v1.ps1",
  "_selftest_triad_restore_negative_payload_length_mismatch_v1.ps1",
  "_selftest_triad_restore_stress_deeper_tree_v1.ps1",
  "_selftest_triad_restore_stress_multi_file_v1.ps1",
  "_selftest_triad_restore_stress_repeated_blocks_v1.ps1",
  "_selftest_triad_restore_stress_tail_partial_v1.ps1",
  "triad_archive_pack_v1.ps1",
  "triad_archive_verify_v1.ps1",
  "triad_archive_extract_v1.ps1",
  "_selftest_triad_archive_v1.ps1",
  "_selftest_triad_archive_extract_v1.ps1",
  "_selftest_triad_archive_negative_tampered_blob_v1.ps1",
  "_selftest_triad_archive_negative_missing_blob_v1.ps1",
  "_selftest_triad_archive_negative_output_not_empty_v1.ps1",
  "_selftest_triad_archive_negative_path_traversal_v1.ps1",
  "triad_transform_apply_v1.ps1",
  "triad_transform_verify_v1.ps1",
  "_selftest_triad_transform_v1.ps1",
  "_selftest_triad_transform_negative_unknown_type_v1.ps1",
  "_selftest_triad_transform_negative_input_sha_mismatch_v1.ps1",
  "_selftest_triad_transform_negative_output_sha_mismatch_v1.ps1",
  "_selftest_triad_transform_negative_transform_id_mismatch_v1.ps1"
)

foreach($name in $ScriptList){
  $p = Join-Path $ScriptsDir $name
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $p) }
  Parse-GateFile $p
}

$Transcript = New-Object System.Collections.Generic.List[string]
[void]$Transcript.Add("TRIAD ENGINE FULL GREEN v1")
[void]$Transcript.Add(("repo_root=" + $RepoRoot))
[void]$Transcript.Add(("freeze_dir=" + $FreezeDir))
[void]$Transcript.Add("")

$Runs = @(
  "_selftest_triad_restore_workflow_v1.ps1",
  "_selftest_triad_restore_vector_v1.ps1",
  "_selftest_triad_restore_negative_block_sha_corruption_v1.ps1",
  "_selftest_triad_restore_negative_missing_block_v1.ps1",
  "_selftest_triad_restore_negative_payload_sha_mismatch_v1.ps1",
  "_selftest_triad_restore_negative_payload_length_mismatch_v1.ps1",
  "_selftest_triad_restore_stress_deeper_tree_v1.ps1",
  "_selftest_triad_restore_stress_multi_file_v1.ps1",
  "_selftest_triad_restore_stress_repeated_blocks_v1.ps1",
  "_selftest_triad_restore_stress_tail_partial_v1.ps1",
  "_selftest_triad_archive_v1.ps1",
  "_selftest_triad_archive_extract_v1.ps1",
  "_selftest_triad_archive_negative_tampered_blob_v1.ps1",
  "_selftest_triad_archive_negative_missing_blob_v1.ps1",
  "_selftest_triad_archive_negative_output_not_empty_v1.ps1",
  "_selftest_triad_archive_negative_path_traversal_v1.ps1",
  "_selftest_triad_transform_v1.ps1",
  "_selftest_triad_transform_negative_unknown_type_v1.ps1",
  "_selftest_triad_transform_negative_input_sha_mismatch_v1.ps1",
  "_selftest_triad_transform_negative_output_sha_mismatch_v1.ps1",
  "_selftest_triad_transform_negative_transform_id_mismatch_v1.ps1"
)

$ResultRows = New-Object System.Collections.Generic.List[string]

foreach($name in $Runs){
  $scriptPath = Join-Path $ScriptsDir $name
  [void]$Transcript.Add(("=== RUN " + $name + " ==="))
  $r = Run-Child $scriptPath ("-RepoRoot `"$RepoRoot`"")
  [void]$Transcript.Add($r.Output.TrimEnd())
  [void]$Transcript.Add("")

  if($r.ExitCode -ne 0){
    $failPath = Join-Path $FreezeDir "full_green_transcript.txt"
    Write-Utf8NoBomLf $failPath (($Transcript.ToArray()) -join "`n")
    Die ("FULL_GREEN_RUN_FAILED: " + $name)
  }

  [void]$ResultRows.Add(("OK|" + $name))
}

$TranscriptPath = Join-Path $FreezeDir "full_green_transcript.txt"
Write-Utf8NoBomLf $TranscriptPath (($Transcript.ToArray()) -join "`n")

$ResultsPath = Join-Path $FreezeDir "full_green_results.txt"
Write-Utf8NoBomLf $ResultsPath (($ResultRows.ToArray()) -join "`n"))

$LedgerLines = New-Object System.Collections.Generic.List[string]
[void]$LedgerLines.Add("# TRIAD Engine Full Green Freeze v1")
[void]$LedgerLines.Add("")
[void]$LedgerLines.Add(("Freeze dir: `" + $FreezeDir + "`"))
[void]$LedgerLines.Add(("Transcript: `" + $TranscriptPath + "`"))
[void]$LedgerLines.Add(("Results: `" + $ResultsPath + "`"))
[void]$LedgerLines.Add("")
[void]$LedgerLines.Add("Included lanes:")
[void]$LedgerLines.Add("")
[void]$LedgerLines.Add("- restore positive workflow")
[void]$LedgerLines.Add("- restore vector")
[void]$LedgerLines.Add("- restore negatives")
[void]$LedgerLines.Add("- restore stress suite")
[void]$LedgerLines.Add("- archive positive pack/verify")
[void]$LedgerLines.Add("- archive extract")
[void]$LedgerLines.Add("- archive negatives")
[void]$LedgerLines.Add("- transform positive")
[void]$LedgerLines.Add("- transform negatives")

$LedgerPath = Join-Path $FreezeDir "FREEZE_LEDGER.md"
Write-Utf8NoBomLf $LedgerPath (($LedgerLines.ToArray()) -join "`n"))

$HashRows = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $FreezeDir -Recurse -File |
  Sort-Object FullName |
  ForEach-Object {
    $rel = $_.FullName.Substring($FreezeDir.Length).TrimStart('\').Replace('\','/')
    $hex = Sha256HexFile $_.FullName
    [void]$HashRows.Add($hex + "  " + $rel)
  }

$ShaPath = Join-Path $FreezeDir "sha256sums.txt"
Write-Utf8NoBomLf $ShaPath (($HashRows.ToArray()) -join "`n"))

$receipt = [ordered]@{
  event        = "triad.engine.full_green.v1"
  freeze_dir   = $FreezeDir
  transcript   = $TranscriptPath
  results      = $ResultsPath
  sha256sums   = $ShaPath
  script_count = $ScriptList.Count
  run_count    = $Runs.Count
  status       = "OK"
}
$receiptLine = ($receipt | ConvertTo-Json -Depth 20 -Compress)

if(Test-Path -LiteralPath $ReceiptPath -PathType Leaf){
  $prev = Read-Utf8 $ReceiptPath
  Write-Utf8NoBomLf $ReceiptPath ($prev + $receiptLine + "`n")
} else {
  Write-Utf8NoBomLf $ReceiptPath ($receiptLine + "`n")
}

Write-Host ("FREEZE_DIR: " + $FreezeDir) -ForegroundColor DarkGray
Write-Host ("TRANSCRIPT: " + $TranscriptPath) -ForegroundColor DarkGray
Write-Host ("SHA256SUMS: " + $ShaPath) -ForegroundColor DarkGray
Write-Host "TRIAD_ENGINE_FULL_GREEN_V1_OK" -ForegroundColor Green
