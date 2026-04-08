param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$NegRoot    = Join-Path $RepoRoot "test_vectors\restore\v1\negative\block_sha_corruption_invalid_v1"
$PlansDir   = Join-Path $NegRoot "plans"
$VerifyPath = Join-Path $RepoRoot "scripts\triad_restore_verify_v1.ps1"
$WorkDir    = Join-Path $RepoRoot "scripts\_work\neg_payload_length_mismatch"
if(-not (Test-Path -LiteralPath $PlansDir -PathType Container)){ Die "NEG_PLANS_DIR_NOT_FOUND" }
if(-not (Test-Path -LiteralPath $VerifyPath -PathType Leaf)){ Die "VERIFY_SCRIPT_NOT_FOUND" }
$Plan = Get-ChildItem -LiteralPath $PlansDir -File | Where-Object { $_.Name -like "*.triad_plan_v1_*.json" } | Sort-Object Name | Select-Object -First 1
if($null -eq $Plan){ Die "MISSING_NEG_PLAN" }
$PlanPath = $Plan.FullName
$PlanObj = (Get-Content -Raw -LiteralPath $PlanPath -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n") | ConvertFrom-Json
if(Test-Path -LiteralPath $WorkDir -PathType Container){ Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$ManifestSrc = [string]$PlanObj.manifest_path
if([string]::IsNullOrWhiteSpace($ManifestSrc)){ Die "PLAN_MANIFEST_PATH_EMPTY" }
if(-not (Test-Path -LiteralPath $ManifestSrc -PathType Leaf)){ Die ("MANIFEST_NOT_FOUND: " + $ManifestSrc) }
$ManifestDst = Join-Path $WorkDir "manifest_mutated.json"
Copy-Item -LiteralPath $ManifestSrc -Destination $ManifestDst -Force
$m = (Get-Content -Raw -LiteralPath $ManifestDst -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n") | ConvertFrom-Json
$entry = $null
foreach($e in @(@($m.entries))){
  if($null -eq $e){ continue }
  $type = ""
  $path = ""
  try { $type = [string]$e.type } catch { $type = "" }
  try { $path = [string]$e.path } catch { $path = "" }
  if($type -eq "file" -and $path -eq "payload.bin"){ $entry = $e; break }
}
if($null -eq $entry){ Die "PAYLOAD_ENTRY_NOT_FOUND" }
$origLen = [int64]$entry.length
if($origLen -lt 1){ Die "PAYLOAD_LENGTH_INVALID" }
$entry.length = ($origLen - 1)
$json = $m | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($ManifestDst,($json.Replace("`r`n","`n").Replace("`r","`n")),([System.Text.UTF8Encoding]::new($false)))
$PlanDst = Join-Path $WorkDir "plan_mutated.json"
$PlanObj.manifest_path = $ManifestDst
$jsonPlan = $PlanObj | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($PlanDst,($jsonPlan.Replace("`r`n","`n").Replace("`r","`n")),([System.Text.UTF8Encoding]::new($false)))
$tmp = [string]$PlanObj.tmp_file
if([string]::IsNullOrWhiteSpace($tmp)){ Die "PLAN_TMP_FILE_EMPTY" }
$tmpDir = Split-Path -Parent $tmp
if($tmpDir -and -not (Test-Path -LiteralPath $tmpDir -PathType Container)){ New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null }
if(-not (Test-Path -LiteralPath $tmp -PathType Leaf)){ New-Item -ItemType File -Path $tmp | Out-Null }
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"
$psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$VerifyPath`" -RepoRoot `"$RepoRoot`" -PlanPath `"$PlanDst`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
[void]$p.Start()
$out = $p.StandardOutput.ReadToEnd() + "`n" + $p.StandardError.ReadToEnd()
$p.WaitForExit()
if($p.ExitCode -eq 0){ Die "NEGATIVE_TEST_FAILED_SHOULD_NOT_PASS" }
if(($out -notmatch "TMP_LEN_MISMATCH") -and ($out -notmatch "PAYLOAD_LENGTH_MISMATCH")){
  Die ("EXPECTED_FAILURE_TOKEN_NOT_FOUND: " + $out)
}
Write-Host ("NEG_PLAN: " + $PlanDst) -ForegroundColor DarkGray
Write-Host "TRIAD_NEGATIVE_VECTOR_PAYLOAD_LENGTH_MISMATCH_V1_SELFTEST_OK" -ForegroundColor Green
