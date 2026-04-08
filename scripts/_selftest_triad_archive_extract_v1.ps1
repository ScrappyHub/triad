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

$RepoRoot    = (Resolve-Path -LiteralPath $RepoRoot).Path
$PackPath    = Join-Path $RepoRoot "scripts\triad_archive_pack_v1.ps1"
$VerifyPath  = Join-Path $RepoRoot "scripts\triad_archive_verify_v1.ps1"
$ExtractPath = Join-Path $RepoRoot "scripts\triad_archive_extract_v1.ps1"

foreach($p in @($PackPath,$VerifyPath,$ExtractPath)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("SCRIPT_NOT_FOUND: " + $p) }
}

$WorkRoot    = Join-Path $RepoRoot "scripts\_work\triad_archive_extract_selftest_v1"
$InputDir    = Join-Path $WorkRoot "input"
$ArchiveDir  = Join-Path $WorkRoot "archive_out"
$OutputDir   = Join-Path $WorkRoot "extract_out"

if(Test-Path -LiteralPath $WorkRoot -PathType Container){
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
Ensure-Dir $InputDir
Ensure-Dir (Join-Path $InputDir "nested")
Ensure-Dir (Join-Path $InputDir "nested\inner")

Write-Utf8NoBomLf (Join-Path $InputDir "a.txt") "alpha"
Write-Utf8NoBomLf (Join-Path $InputDir "nested\b.txt") "beta"
Write-Utf8NoBomLf (Join-Path $InputDir "nested\inner\c.txt") "gamma"

$bytes = New-Object byte[] 4096
for($i=0; $i -lt $bytes.Length; $i++){ $bytes[$i] = [byte](($i * 9 + 5) % 251) }
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

$psi3 = New-Object System.Diagnostics.ProcessStartInfo
$psi3.FileName = "powershell.exe"
$psi3.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ExtractPath`" -RepoRoot `"$RepoRoot`" -ArchiveDir `"$ArchiveDir`" -OutputDir `"$OutputDir`""
$psi3.UseShellExecute = $false
$psi3.RedirectStandardOutput = $true
$psi3.RedirectStandardError = $true
$psi3.CreateNoWindow = $true
$p3 = New-Object System.Diagnostics.Process
$p3.StartInfo = $psi3
[void]$p3.Start()
$out3 = $p3.StandardOutput.ReadToEnd() + "`n" + $p3.StandardError.ReadToEnd()
$p3.WaitForExit()
if($p3.ExitCode -ne 0){ Die ("EXTRACT_FAILED: " + $out3) }
if($out3 -notmatch "TRIAD_ARCHIVE_EXTRACT_V1_OK"){ Die ("EXTRACT_TOKEN_MISSING: " + $out3) }

$srcFiles = Get-ChildItem -LiteralPath $InputDir -Recurse -File | Sort-Object FullName
$dstFiles = Get-ChildItem -LiteralPath $OutputDir -Recurse -File | Sort-Object FullName

if($srcFiles.Count -ne $dstFiles.Count){ Die "EXTRACT_FILE_COUNT_MISMATCH" }

foreach($src in $srcFiles){
  $rel = $src.FullName.Substring($InputDir.Length).TrimStart('\').Replace('\','/')
  $dst = Join-Path $OutputDir ($rel -replace '/','\')
  if(-not (Test-Path -LiteralPath $dst -PathType Leaf)){ Die ("EXTRACTED_FILE_MISSING: " + $dst) }

  $srcSha = Sha256HexFile $src.FullName
  $dstSha = Sha256HexFile $dst
  if($srcSha -ne $dstSha){ Die ("EXTRACTED_FILE_SHA_MISMATCH: " + $rel) }

  $srcLen = [int64]$src.Length
  $dstLen = [int64](Get-Item -LiteralPath $dst).Length
  if($srcLen -ne $dstLen){ Die ("EXTRACTED_FILE_SIZE_MISMATCH: " + $rel) }
}

Write-Host ("ARCHIVE_DIR: " + $ArchiveDir) -ForegroundColor DarkGray
Write-Host ("OUTPUT_DIR: " + $OutputDir) -ForegroundColor DarkGray
Write-Host "TRIAD_ARCHIVE_EXTRACT_V1_SELFTEST_OK" -ForegroundColor Green
