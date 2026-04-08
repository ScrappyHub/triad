param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$NegRoot    = Join-Path $RepoRoot "test_vectors\restore\v1\negative\block_sha_corruption_invalid_v1"
$PlansDir   = Join-Path $NegRoot "plans"
$VerifyPath = Join-Path $RepoRoot "scripts\triad_restore_verify_v1.ps1"
$WorkDir    = Join-Path $RepoRoot "scripts\_work\neg_payload_sha_mismatch"
if(-not (Test-Path $PlansDir)){ Die "NEG_PLANS_DIR_NOT_FOUND" }
if(-not (Test-Path $VerifyPath)){ Die "VERIFY_SCRIPT_NOT_FOUND" }
$Plan = Get-ChildItem $PlansDir -File | Where-Object { $_.Name -like "*.triad_plan_v1_*.json" } | Sort-Object Name | Select-Object -First 1
if($null -eq $Plan){ Die "MISSING_NEG_PLAN" }
$PlanPath = $Plan.FullName
$PlanObj = Get-Content -Raw $PlanPath | ConvertFrom-Json
if(Test-Path $WorkDir){ Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$ManifestSrc = $PlanObj.manifest_path
$ManifestDst = Join-Path $WorkDir "manifest_mutated.json"
Copy-Item $ManifestSrc $ManifestDst -Force
$m = Get-Content -Raw $ManifestDst | ConvertFrom-Json
$entry = $null
foreach($e in $m.entries){ if($e.path -eq "payload.bin"){ $entry = $e; break } }
if($null -eq $entry){ Die "PAYLOAD_ENTRY_NOT_FOUND" }
$entry.sha256 = "0000000000000000000000000000000000000000000000000000000000000000"
$m | ConvertTo-Json -Depth 100 | Set-Content -Encoding UTF8 $ManifestDst
$PlanDst = Join-Path $WorkDir "plan_mutated.json"
$PlanObj.manifest_path = $ManifestDst
$PlanObj | ConvertTo-Json -Depth 100 | Set-Content -Encoding UTF8 $PlanDst
$tmp = $PlanObj.tmp_file
$tmpDir = Split-Path $tmp
if(-not (Test-Path $tmpDir)){ New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null }
if(-not (Test-Path $tmp)){ New-Item -ItemType File -Path $tmp | Out-Null }
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"
$psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$VerifyPath`" -RepoRoot `"$RepoRoot`" -PlanPath `"$PlanDst`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
[void]$p.Start()
$out = $p.StandardOutput.ReadToEnd() + "`n" + $p.StandardError.ReadToEnd()
$p.WaitForExit()
if($p.ExitCode -eq 0){ Die "NEGATIVE_TEST_FAILED_SHOULD_NOT_PASS" }
if(($out -notmatch "TMP_SHA_MISMATCH") -and ($out -notmatch "PAYLOAD_SHA_MISMATCH")){
  Die ("EXPECTED_FAILURE_TOKEN_NOT_FOUND: " + $out)
}
Write-Host ("NEG_PLAN: " + $PlanDst) -ForegroundColor DarkGray
Write-Host "TRIAD_NEGATIVE_VECTOR_PAYLOAD_SHA_MISMATCH_V1_SELFTEST_OK" -ForegroundColor Green
