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

$RepoRoot  = (Resolve-Path -LiteralPath $RepoRoot).Path
$PackPath  = Join-Path $RepoRoot "scripts\triad_archive_pack_v1.ps1"
$VerifyPath = Join-Path $RepoRoot "scripts\triad_archive_verify_v1.ps1"

if(-not (Test-Path -LiteralPath $PackPath -PathType Leaf)){ Die ("PACK_SCRIPT_NOT_FOUND: " + $PackPath) }
if(-not (Test-Path -LiteralPath $VerifyPath -PathType Leaf)){ Die ("VERIFY_SCRIPT_NOT_FOUND: " + $VerifyPath) }

$WorkRoot   = Join-Path $RepoRoot "scripts\_work\triad_archive_selftest_v1"
$InputDir   = Join-Path $WorkRoot "input"
$ArchiveDir = Join-Path $WorkRoot "archive_out"

if(Test-Path -LiteralPath $WorkRoot -PathType Container){
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
Ensure-Dir $InputDir
Ensure-Dir (Join-Path $InputDir "nested")

Write-Utf8NoBomLf (Join-Path $InputDir "a.txt") "alpha"
Write-Utf8NoBomLf (Join-Path $InputDir "nested\b.txt") "beta"

$bytes = New-Object byte[] 1024
for($i=0; $i -lt $bytes.Length; $i++){ $bytes[$i] = [byte](($i * 3 + 7) % 251) }
[System.IO.File]::WriteAllBytes((Join-Path $InputDir "payload.bin"),$bytes)

$psi1 = New-Object System.Diagnostics.ProcessStartInfo
$psi1.FileName = "powershell.exe"
$psi1.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PackPath`" -RepoRoot `"$RepoRoot`" -InputDir `"$InputDir`" -ArchiveDir `"$ArchiveDir`""
$psi1.UseShellExecute = $false
$psi1.RedirectStandardOutput = $true
$psi1.RedirectStandardError = $true
$psi1.CreateNoWindow = $true

$p1 = New-Object System.Diagnostics.Process
$p1.StartInfo = $psi1
[void]$p1.Start()
$out1 = $p1.StandardOutput.ReadToEnd() + "`n" + $p1.StandardError.ReadToEnd()
$p1.WaitForExit()

if($p1.ExitCode -ne 0){ Die ("PACK_FAILED: " + $out1) }
if($out1 -notmatch "TRIAD_ARCHIVE_PACK_V1_OK"){ Die ("PACK_TOKEN_MISSING: " + $out1) }

$psi2 = New-Object System.Diagnostics.ProcessStartInfo
$psi2.FileName = "powershell.exe"
$psi2.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$VerifyPath`" -RepoRoot `"$RepoRoot`" -ArchiveDir `"$ArchiveDir`""
$psi2.UseShellExecute = $false
$psi2.RedirectStandardOutput = $true
$psi2.RedirectStandardError = $true
$psi2.CreateNoWindow = $true

$p2 = New-Object System.Diagnostics.Process
$p2.StartInfo = $psi2
[void]$p2.Start()
$out2 = $p2.StandardOutput.ReadToEnd() + "`n" + $p2.StandardError.ReadToEnd()
$p2.WaitForExit()

if($p2.ExitCode -ne 0){ Die ("VERIFY_FAILED: " + $out2) }
if($out2 -notmatch "TRIAD_ARCHIVE_VERIFY_V1_OK"){ Die ("VERIFY_TOKEN_MISSING: " + $out2) }

Write-Host ("ARCHIVE_DIR: " + $ArchiveDir) -ForegroundColor DarkGray
Write-Host "TRIAD_ARCHIVE_V1_SELFTEST_OK" -ForegroundColor Green
