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

$RepoRoot   = (Resolve-Path -LiteralPath $RepoRoot).Path
$ApplyPath  = Join-Path $RepoRoot "scripts\triad_transform_apply_v1.ps1"
$VerifyPath = Join-Path $RepoRoot "scripts\triad_transform_verify_v1.ps1"

foreach($p in @($ApplyPath,$VerifyPath)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("SCRIPT_NOT_FOUND: " + $p) }
}

$WorkRoot     = Join-Path $RepoRoot "scripts\_work\triad_transform_negative_output_sha_mismatch_v1"
$InputPath    = Join-Path $WorkRoot "input.txt"
$OutputPath   = Join-Path $WorkRoot "output.txt"

if(Test-Path -LiteralPath $WorkRoot -PathType Container){
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
Ensure-Dir $WorkRoot
Write-Utf8NoBomLf $InputPath " alpha   `r`n beta`t`t`r`n gamma   "

$r1 = Run-Child $ApplyPath ("-RepoRoot `"$RepoRoot`" -TransformType `"trim_trailing_whitespace`" -InputPath `"$InputPath`" -OutputPath `"$OutputPath`"")
if($r1.ExitCode -ne 0){ Die ("APPLY_FAILED: " + $r1.Output) }
if($r1.Output -notmatch "TRIAD_TRANSFORM_APPLY_V1_OK"){ Die ("APPLY_TOKEN_MISSING: " + $r1.Output) }

$ManifestPath = $OutputPath + ".transform_manifest.json"
if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){ Die "TRANSFORM_MANIFEST_NOT_WRITTEN" }

Write-Utf8NoBomLf $OutputPath "mutated output after manifest"

$r2 = Run-Child $VerifyPath ("-RepoRoot `"$RepoRoot`" -ManifestPath `"$ManifestPath`"")
if($r2.ExitCode -eq 0){ Die "NEGATIVE_TEST_FAILED_SHOULD_NOT_PASS" }
if($r2.Output -notmatch "OUTPUT_SHA_MISMATCH"){ Die ("EXPECTED_FAILURE_TOKEN_NOT_FOUND: " + $r2.Output) }

Write-Host ("NEG_MANIFEST: " + $ManifestPath) -ForegroundColor DarkGray
Write-Host "TRIAD_TRANSFORM_NEGATIVE_OUTPUT_SHA_MISMATCH_V1_SELFTEST_OK" -ForegroundColor Green
