param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

$RepoRoot = (Resolve-Path $RepoRoot).Path
$WorkRoot = Join-Path $RepoRoot "scripts\_work\triad_dir_neg_tampered_block_v1"
$InputDir = Join-Path $RepoRoot "scripts\_work\triad_archive_selftest_v1\input"
$Blockmap = Join-Path $WorkRoot "blockmap.json"
$StoreDir = Join-Path $WorkRoot "store"
$RestoreDir = Join-Path $WorkRoot "restored"

if(Test-Path $WorkRoot){ Remove-Item $WorkRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

& (Join-Path $RepoRoot "scripts\triad_blockmap_dir_v1.ps1") -RepoRoot $RepoRoot -InputDir $InputDir -OutputManifest $Blockmap | Out-Null
& (Join-Path $RepoRoot "scripts\triad_block_store_export_v1.ps1") -RepoRoot $RepoRoot -InputDir $InputDir -BlockmapManifest $Blockmap -OutputStoreDir $StoreDir | Out-Null

$blk = Get-ChildItem (Join-Path $StoreDir "blocks\*.blk") | Select-Object -First 1
if(-not $blk){ Die "NO_BLOCK_FOUND" }
[byte[]]$b = [System.IO.File]::ReadAllBytes($blk.FullName)
$b[0] = $b[0] -bxor 0xFF
[System.IO.File]::WriteAllBytes($blk.FullName, $b)

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"
$psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$RepoRoot\scripts\triad_restore_dir_from_block_store_v1.ps1`" -RepoRoot `"$RepoRoot`" -StoreDir `"$StoreDir`" -OutputDir `"$RestoreDir`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
[void]$p.Start()
$out = $p.StandardOutput.ReadToEnd() + "`n" + $p.StandardError.ReadToEnd()
$p.WaitForExit()

if($p.ExitCode -eq 0){ Die "NEGATIVE_SHOULD_FAIL" }
if($out -notmatch "BLOCK_HASH_MISMATCH"){ Die ("EXPECTED_BLOCK_HASH_MISMATCH_NOT_FOUND: " + $out) }

Write-Host "TRIAD_DIR_NEGATIVE_TAMPERED_BLOCK_V1_OK"
