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

function Run-Child([string]$Script,[string]$Arguments){
  if(-not (Test-Path -LiteralPath $Script -PathType Leaf)){ Die ("SCRIPT_NOT_FOUND: " + $Script) }

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

  return [pscustomobject]@{
    ExitCode = $p.ExitCode
    Output   = ($stdout + "`n" + $stderr)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"

$RunDir = Join-Path $RepoRoot ("proofs\freeze\triad_tier0_" + (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ"))
Ensure-Dir $RunDir

$TranscriptPath = Join-Path $RunDir "full_green_transcript.txt"
$ShaPath        = Join-Path $RunDir "sha256sums.txt"
$ReceiptPath    = Join-Path $RunDir "triad.freeze.receipt.json"

$Transcript = New-Object System.Collections.Generic.List[string]

function Add-Transcript([string]$Text){
  [void]$Transcript.Add($Text)
}

$AuthoritativeScripts = @(
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

Add-Transcript("TRIAD FULL GREEN RUNNER v1")
Add-Transcript("repo_root: " + $RepoRoot)
Add-Transcript("run_dir: " + $RunDir)
Add-Transcript("")

foreach($name in $AuthoritativeScripts){
  $path = Join-Path $ScriptsDir $name
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){ Die ("AUTHORITATIVE_SCRIPT_MISSING: " + $path) }
  Parse-GateFile $path
  Add-Transcript("PARSE_OK: " + $path)
}

$Selftests = @(
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

foreach($name in $Selftests){
  $path = Join-Path $ScriptsDir $name
  Add-Transcript("")
  Add-Transcript("RUN: " + $path)

  $r = Run-Child $path ("-RepoRoot `"$RepoRoot`"")
  Add-Transcript($r.Output)

  if($r.ExitCode -ne 0){
    Write-Utf8NoBomLf $TranscriptPath (($Transcript.ToArray()) -join "`n")
    Die ("SELFTEST_FAILED: " + $path)
  }

  Add-Transcript("RUN_OK: " + $path)
}

Write-Utf8NoBomLf $TranscriptPath (($Transcript.ToArray()) -join "`n")

$HashRows = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $RunDir -Recurse -File |
  Sort-Object FullName |
  ForEach-Object {
    $rel = $_.FullName.Substring($RunDir.Length).TrimStart('\').Replace('\','/')
    $hex = Sha256HexFile $_.FullName
    [void]$HashRows.Add($hex + "  " + $rel)
  }

Write-Utf8NoBomLf $ShaPath (($HashRows.ToArray() -join "`n"))

$Receipt = [ordered]@{
  event            = "triad.freeze.v1"
  run_dir          = $RunDir
  transcript_path  = $TranscriptPath
  sha256sums_path  = $ShaPath
  authoritative_script_count = @(@($AuthoritativeScripts)).Count
  selftest_count   = @(@($Selftests)).Count
  status           = "OK"
}
Write-Utf8NoBomLf $ReceiptPath (($Receipt | ConvertTo-Json -Depth 20 -Compress))

Write-Host ("RUN_DIR: " + $RunDir) -ForegroundColor Yellow
Write-Host ("TRANSCRIPT_OK: " + $TranscriptPath) -ForegroundColor Green
Write-Host ("SHA256SUMS_OK: " + $ShaPath) -ForegroundColor Green
Write-Host ("FREEZE_RECEIPT_OK: " + $ReceiptPath) -ForegroundColor Green
Write-Host "TRIAD_TIER0_FULL_GREEN" -ForegroundColor Green
