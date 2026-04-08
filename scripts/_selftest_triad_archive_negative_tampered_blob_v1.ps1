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
  return [pscustomobject]@{
    ExitCode = $p.ExitCode
    Output   = $stdout + "`n" + $stderr
  }
}

$RepoRoot    = (Resolve-Path -LiteralPath $RepoRoot).Path
$PackPath    = Join-Path $RepoRoot "scripts\triad_archive_pack_v1.ps1"
$ExtractPath = Join-Path $RepoRoot "scripts\triad_archive_extract_v1.ps1"

foreach($p in @($PackPath,$ExtractPath)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("SCRIPT_NOT_FOUND: " + $p) }
}

$WorkRoot   = Join-Path $RepoRoot "scripts\_work\triad_archive_negative_tampered_blob_v1"
$InputDir   = Join-Path $WorkRoot "input"
$ArchiveDir = Join-Path $WorkRoot "archive_out"
$OutputDir  = Join-Path $WorkRoot "extract_out"

if(Test-Path -LiteralPath $WorkRoot -PathType Container){
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
Ensure-Dir $InputDir
Write-Utf8NoBomLf (Join-Path $InputDir "a.txt") "alpha"
$bytes = New-Object byte[] 1024
for($i=0; $i -lt $bytes.Length; $i++){ $bytes[$i] = [byte](($i * 3 + 7) % 251) }
[System.IO.File]::WriteAllBytes((Join-Path $InputDir "payload.bin"),$bytes)

$r1 = Run-Child $PackPath ("-RepoRoot `"$RepoRoot`" -InputDir `"$InputDir`" -ArchiveDir `"$ArchiveDir`"")
if($r1.ExitCode -ne 0){ Die ("PACK_FAILED: " + $r1.Output) }
if($r1.Output -notmatch "TRIAD_ARCHIVE_PACK_V1_OK"){ Die ("PACK_TOKEN_MISSING: " + $r1.Output) }

$BlobDir = Join-Path $ArchiveDir "blobs"
$Blob = Get-ChildItem -LiteralPath $BlobDir -File | Sort-Object Name | Select-Object -First 1
if($null -eq $Blob){ Die "NO_BLOB_FOUND" }

$orig = [System.IO.File]::ReadAllBytes($Blob.FullName)
$mut  = New-Object byte[] $orig.Length
[Array]::Copy($orig,$mut,$orig.Length)
if($mut.Length -eq 0){ Die "EMPTY_BLOB_UNEXPECTED" }
$mut[0] = [byte](($mut[0] + 1) % 256)
[System.IO.File]::WriteAllBytes($Blob.FullName,$mut)

try {
  $r2 = Run-Child $ExtractPath ("-RepoRoot `"$RepoRoot`" -ArchiveDir `"$ArchiveDir`" -OutputDir `"$OutputDir`"")
  if($r2.ExitCode -eq 0){ Die "NEGATIVE_TEST_FAILED_SHOULD_NOT_PASS" }
  if($r2.Output -notmatch "BLOB_SHA_MISMATCH"){ Die ("EXPECTED_FAILURE_TOKEN_NOT_FOUND: " + $r2.Output) }
  Write-Host ("NEG_BLOB: " + $Blob.FullName) -ForegroundColor DarkGray
  Write-Host "TRIAD_ARCHIVE_NEGATIVE_TAMPERED_BLOB_V1_SELFTEST_OK" -ForegroundColor Green
}
finally {
  [System.IO.File]::WriteAllBytes($Blob.FullName,$orig)
}
