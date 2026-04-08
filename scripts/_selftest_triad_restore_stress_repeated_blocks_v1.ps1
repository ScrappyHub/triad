param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunPath = Join-Path $RepoRoot "scripts\_RUN_triad_restore_stress_repeated_blocks_v1.ps1"
if(-not (Test-Path -LiteralPath $RunPath -PathType Leaf)){ Die ("MISSING_RUNNER: " + $RunPath) }
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"
$psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$RunPath`" -RepoRoot `"$RepoRoot`""
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
$out = $stdout + "`n" + $stderr
if($p.ExitCode -ne 0){ Die ("RUNNER_EXIT_NONZERO: " + $out) }
if($out -notmatch "TRIAD_RESTORE_STRESS_REPEATED_BLOCKS_V1_OK"){ Die ("MISSING_PASS_TOKEN: " + $out) }
Write-Host "TRIAD_RESTORE_STRESS_REPEATED_BLOCKS_V1_SELFTEST_OK" -ForegroundColor Green
