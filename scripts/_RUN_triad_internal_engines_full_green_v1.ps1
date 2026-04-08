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

function Run-ScriptCapture([string]$ScriptPath,[string]$RepoRoot,[string]$RunDir,[string]$Name,[string]$PassToken){
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $ScriptPath) }

  $stdoutPath = Join-Path $RunDir ($Name + ".stdout.txt")
  $stderrPath = Join-Path $RunDir ($Name + ".stderr.txt")

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`" -RepoRoot `"$RepoRoot`""
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

  Write-Utf8NoBomLf $stdoutPath $stdout
  Write-Utf8NoBomLf $stderrPath $stderr

  if($p.ExitCode -ne 0){
    Die ("RUN_NONZERO: " + $Name + " stdout=" + $stdoutPath + " stderr=" + $stderrPath)
  }

  $all = $stdout + "`n" + $stderr
  if($all -notmatch [regex]::Escape($PassToken)){
    Die ("PASS_TOKEN_MISSING: " + $Name + " token=" + $PassToken + " stdout=" + $stdoutPath + " stderr=" + $stderrPath)
  }

  Write-Host ("STEP_OK: " + $Name) -ForegroundColor Green
  return [pscustomobject]@{
    Name = $Name
    StdoutPath = $stdoutPath
    StderrPath = $stderrPath
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts"

$AuthoritativeScripts = @(
  "triad_restore_prepare_v1.ps1",
  "triad_restore_verify_v1.ps1",
  "triad_restore_commit_v1.ps1",
  "_selftest_triad_restore_workflow_v1.ps1",
  "_RUN_triad_restore_vector_materialize_v1.ps1",
  "_selftest_triad_restore_vector_v1.ps1",
  "_RUN_triad_restore_stress_seed_materialize_v1.ps1",
  "_selftest_triad_restore_stress_seed_v1.ps1",
  "_selftest_triad_restore_negative_block_sha_corruption_v1.ps1",
  "_selftest_triad_restore_negative_missing_block_v1.ps1",
  "_selftest_triad_restore_negative_payload_sha_mismatch_v1.ps1",
  "_selftest_triad_restore_negative_payload_length_mismatch_v1.ps1",
  "_RUN_triad_restore_stress_deeper_tree_v1.ps1",
  "_selftest_triad_restore_stress_deeper_tree_v1.ps1",
  "_RUN_triad_restore_stress_multi_file_v1.ps1",
  "_selftest_triad_restore_stress_multi_file_v1.ps1",
  "_RUN_triad_restore_stress_repeated_blocks_v1.ps1",
  "_selftest_triad_restore_stress_repeated_blocks_v1.ps1",
  "_RUN_triad_restore_stress_tail_partial_v1.ps1",
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

foreach($name in $AuthoritativeScripts){
  $p = Join-Path $ScriptsDir $name
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("AUTHORITATIVE_SCRIPT_MISSING: " + $p) }
  Parse-GateFile $p
}

$RunRoot = Join-Path $RepoRoot "proofs\receipts\triad_internal_engines_full_green"
Ensure-Dir $RunRoot
$Stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
$RunDir = Join-Path $RunRoot $Stamp
Ensure-Dir $RunDir

$Steps = @(
  [pscustomobject]@{ Script = "_selftest_triad_restore_workflow_v1.ps1"; Name = "restore_workflow"; Token = "TRIAD RESTORE WORKFLOW SELFTEST: PASS" },
  [pscustomobject]@{ Script = "_selftest_triad_restore_vector_v1.ps1"; Name = "restore_vector"; Token = "TRIAD_RESTORE_VECTOR_V1_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_restore_stress_seed_v1.ps1"; Name = "restore_stress_seed"; Token = "TRIAD_RESTORE_STRESS_SEED_V1_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_restore_negative_block_sha_corruption_v1.ps1"; Name = "restore_neg_block_sha"; Token = "TRIAD_NEGATIVE_VECTOR_BLOCK_SHA_CORRUPTION_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_restore_negative_missing_block_v1.ps1"; Name = "restore_neg_missing_block"; Token = "TRIAD_NEGATIVE_VECTOR_MISSING_BLOCK_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_restore_negative_payload_sha_mismatch_v1.ps1"; Name = "restore_neg_payload_sha"; Token = "TRIAD_NEGATIVE_VECTOR_PAYLOAD_SHA_MISMATCH_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_restore_negative_payload_length_mismatch_v1.ps1"; Name = "restore_neg_payload_len"; Token = "TRIAD_NEGATIVE_VECTOR_PAYLOAD_LENGTH_MISMATCH_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_restore_stress_deeper_tree_v1.ps1"; Name = "restore_stress_deeper_tree"; Token = "TRIAD_RESTORE_STRESS_DEEPER_TREE_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_restore_stress_multi_file_v1.ps1"; Name = "restore_stress_multi_file"; Token = "TRIAD_RESTORE_STRESS_MULTI_FILE_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_restore_stress_repeated_blocks_v1.ps1"; Name = "restore_stress_repeated"; Token = "TRIAD_RESTORE_STRESS_REPEATED_BLOCKS_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_restore_stress_tail_partial_v1.ps1"; Name = "restore_stress_tail_partial"; Token = "TRIAD_RESTORE_STRESS_TAIL_PARTIAL_V1_SELFTEST_OK" },

  [pscustomobject]@{ Script = "_selftest_triad_archive_v1.ps1"; Name = "archive_positive"; Token = "TRIAD_ARCHIVE_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_archive_extract_v1.ps1"; Name = "archive_extract"; Token = "TRIAD_ARCHIVE_EXTRACT_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_archive_negative_tampered_blob_v1.ps1"; Name = "archive_neg_tampered_blob"; Token = "TRIAD_ARCHIVE_NEGATIVE_TAMPERED_BLOB_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_archive_negative_missing_blob_v1.ps1"; Name = "archive_neg_missing_blob"; Token = "TRIAD_ARCHIVE_NEGATIVE_MISSING_BLOB_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_archive_negative_output_not_empty_v1.ps1"; Name = "archive_neg_output_not_empty"; Token = "TRIAD_ARCHIVE_NEGATIVE_OUTPUT_NOT_EMPTY_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_archive_negative_path_traversal_v1.ps1"; Name = "archive_neg_path_traversal"; Token = "TRIAD_ARCHIVE_NEGATIVE_PATH_TRAVERSAL_V1_SELFTEST_OK" },

  [pscustomobject]@{ Script = "_selftest_triad_transform_v1.ps1"; Name = "transform_positive"; Token = "TRIAD_TRANSFORM_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_transform_negative_unknown_type_v1.ps1"; Name = "transform_neg_unknown"; Token = "TRIAD_TRANSFORM_NEGATIVE_UNKNOWN_TYPE_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_transform_negative_input_sha_mismatch_v1.ps1"; Name = "transform_neg_input_sha"; Token = "TRIAD_TRANSFORM_NEGATIVE_INPUT_SHA_MISMATCH_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_transform_negative_output_sha_mismatch_v1.ps1"; Name = "transform_neg_output_sha"; Token = "TRIAD_TRANSFORM_NEGATIVE_OUTPUT_SHA_MISMATCH_V1_SELFTEST_OK" },
  [pscustomobject]@{ Script = "_selftest_triad_transform_negative_transform_id_mismatch_v1.ps1"; Name = "transform_neg_id"; Token = "TRIAD_TRANSFORM_NEGATIVE_TRANSFORM_ID_MISMATCH_V1_SELFTEST_OK" }
)

$Results = New-Object System.Collections.Generic.List[object]
foreach($s in $Steps){
  $scriptPath = Join-Path $ScriptsDir $s.Script
  $r = Run-ScriptCapture -ScriptPath $scriptPath -RepoRoot $RepoRoot -RunDir $RunDir -Name $s.Name -PassToken $s.Token
  [void]$Results.Add($r)
}

$HashRows = New-Object System.Collections.Generic.List[string]

foreach($name in $AuthoritativeScripts){
  $p = Join-Path $ScriptsDir $name
  [void]$HashRows.Add((Sha256HexFile $p) + "  scripts/" + $name)
}

$extraFiles = Get-ChildItem -LiteralPath $RunDir -File | Sort-Object Name
foreach($f in $extraFiles){
  [void]$HashRows.Add((Sha256HexFile $f.FullName) + "  run/" + $f.Name)
}

$ShaPath = Join-Path $RunDir "sha256sums.txt"
Write-Utf8NoBomLf $ShaPath (($HashRows.ToArray()) -join "`n")

$SummaryPath = Join-Path $RunDir "SUMMARY.txt"
$SummaryLines = New-Object System.Collections.Generic.List[string]
[void]$SummaryLines.Add("TRIAD internal engines full green run")
[void]$SummaryLines.Add("run_dir=" + $RunDir)
[void]$SummaryLines.Add("step_count=" + $Steps.Count)
foreach($s in $Steps){
  [void]$SummaryLines.Add("OK " + $s.Name + " token=" + $s.Token)
}
Write-Utf8NoBomLf $SummaryPath (($SummaryLines.ToArray()) -join "`n"))

$ReceiptPath = Join-Path $RepoRoot "proofs\receipts\triad.internal_engines.full_green.v1.ndjson"
$receipt = [ordered]@{
  event       = "triad.internal_engines.full_green.v1"
  run_dir     = $RunDir
  step_count  = $Steps.Count
  sha256sums  = $ShaPath
  summary     = $SummaryPath
  status      = "OK"
}
$receiptLine = ($receipt | ConvertTo-Json -Depth 20 -Compress)
if(Test-Path -LiteralPath $ReceiptPath -PathType Leaf){
  $prev = Read-Utf8 $ReceiptPath
  Write-Utf8NoBomLf $ReceiptPath ($prev + $receiptLine + "`n")
} else {
  Write-Utf8NoBomLf $ReceiptPath ($receiptLine + "`n")
}

Write-Host ("RUN_DIR: " + $RunDir) -ForegroundColor DarkGray
Write-Host ("SHA256SUMS: " + $ShaPath) -ForegroundColor DarkGray
Write-Host ("SUMMARY: " + $SummaryPath) -ForegroundColor DarkGray
Write-Host "TRIAD_TIER0_INTERNAL_ENGINES_FULL_GREEN" -ForegroundColor Green
