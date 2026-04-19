param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

$RepoRoot = (Resolve-Path $RepoRoot).Path
$WorkRoot = Join-Path $RepoRoot "scripts\_work\triad_dir_neg_tampered_manifest_v1"
$InputDir = Join-Path $RepoRoot "scripts\_work\triad_archive_selftest_v1\input"
$Blockmap = Join-Path $WorkRoot "blockmap.json"
$StoreDir = Join-Path $WorkRoot "store"
$RestoreDir = Join-Path $WorkRoot "restored"

if(Test-Path -LiteralPath $WorkRoot){
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

& (Join-Path $RepoRoot "scripts\triad_blockmap_dir_v1.ps1") `
  -RepoRoot $RepoRoot `
  -InputDir $InputDir `
  -OutputManifest $Blockmap | Out-Null

& (Join-Path $RepoRoot "scripts\triad_block_store_export_v1.ps1") `
  -RepoRoot $RepoRoot `
  -InputDir $InputDir `
  -BlockmapManifest $Blockmap `
  -OutputStoreDir $StoreDir | Out-Null

$ManifestPath = Join-Path $StoreDir "blockmap_dir_manifest.json"
if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){ Die "MANIFEST_NOT_FOUND" }

$raw = Get-Content -LiteralPath $ManifestPath -Raw

$pattern = '"sha256"\s*:\s*"([0-9a-f]{64})"'
$replacement = '"sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"'
$newRaw = [System.Text.RegularExpressions.Regex]::Replace($raw, $pattern, $replacement, 1)

if($newRaw -eq $raw){ Die "MANIFEST_SHA_FIELD_NOT_FOUND" }

[System.IO.File]::WriteAllText($ManifestPath, $newRaw, (New-Object System.Text.UTF8Encoding($false)))

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

if(($out -notmatch "BLOCK_HASH_MISMATCH") -and ($out -notmatch "BLOCK_FILE_MISSING")){
  Die ("EXPECTED_MANIFEST_FAILURE_NOT_FOUND: " + $out)
}

Write-Host "TRIAD_DIR_NEGATIVE_TAMPERED_MANIFEST_V1_OK"
