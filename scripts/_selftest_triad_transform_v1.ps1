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

$WorkRoot     = Join-Path $RepoRoot "scripts\_work\triad_transform_selftest_v1"
$InputPath    = Join-Path $WorkRoot "input.txt"
$OutputPath   = Join-Path $WorkRoot "output.txt"

if(Test-Path -LiteralPath $WorkRoot -PathType Container){
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
Ensure-Dir $WorkRoot

$raw = " alpha   `r`n beta`t`t`r`n gamma   "
Write-Utf8NoBomLf $InputPath $raw

$r1 = Run-Child $ApplyPath ("-RepoRoot `"$RepoRoot`" -TransformType `"trim_trailing_whitespace`" -InputPath `"$InputPath`" -OutputPath `"$OutputPath`"")
if($r1.ExitCode -ne 0){ Die ("APPLY_FAILED: " + $r1.Output) }
if($r1.Output -notmatch "TRIAD_TRANSFORM_APPLY_V1_OK"){ Die ("APPLY_TOKEN_MISSING: " + $r1.Output) }

$ManifestPath = $OutputPath + ".transform_manifest.json"
if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){ Die "TRANSFORM_MANIFEST_NOT_WRITTEN" }

$r2 = Run-Child $VerifyPath ("-RepoRoot `"$RepoRoot`" -ManifestPath `"$ManifestPath`"")
if($r2.ExitCode -ne 0){ Die ("VERIFY_FAILED: " + $r2.Output) }
if($r2.Output -notmatch "TRIAD_TRANSFORM_VERIFY_V1_OK"){ Die ("VERIFY_TOKEN_MISSING: " + $r2.Output) }

$got = Read-Utf8 $OutputPath
$expected = " alpha`n beta`n gamma`n"
if($got -ne $expected){ Die ("TRANSFORM_OUTPUT_UNEXPECTED: [" + $got + "]") }

Write-Host ("MANIFEST: " + $ManifestPath) -ForegroundColor DarkGray
Write-Host "TRIAD_TRANSFORM_V1_SELFTEST_OK" -ForegroundColor Green
