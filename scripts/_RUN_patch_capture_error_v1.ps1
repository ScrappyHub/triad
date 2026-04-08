param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die ("MISSING_REPO: " + $RepoRoot) }
$ScriptsDir = Join-Path $RepoRoot "scripts"
$Target = Join-Path $ScriptsDir "_PATCH_tree_transcript_dual_v1.ps1"
if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){ Die ("MISSING_PATCH: " + $Target) }

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$OutDir = Join-Path $ScriptsDir ("_run_patch_capture_" + $ts)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Report = Join-Path $OutDir "patch_failure_report.txt"

try {
  & $Target -RepoRoot $RepoRoot
  Write-Utf8NoBomLf $Report ("OK: patch ran without error`npatch: " + $Target + "`n")
  Write-Host "OK: patch ran without error (unexpected, good)" -ForegroundColor Green
  Write-Host ("report: {0}" -f $Report) -ForegroundColor DarkGray
}
catch {
  $e = $_.Exception
  $inv = $_.InvocationInfo

  $ln = -1
  $lineTxt = ""
  $posMsg = ""
  if ($inv) {
    if ($inv.ScriptLineNumber) { $ln = [int]$inv.ScriptLineNumber }
    if ($inv.Line) { $lineTxt = [string]$inv.Line }
    $posMsg = ("at {0}:{1}:{2}" -f $inv.ScriptName, $inv.ScriptLineNumber, $inv.OffsetInLine)
  }

  $msg = New-Object System.Collections.Generic.List[string]
  [void]$msg.Add("PATCH_FAILED")
  [void]$msg.Add(("patch: {0}" -f $Target))
  [void]$msg.Add(("error_type: {0}" -f $e.GetType().FullName))
  [void]$msg.Add(("message: {0}" -f $e.Message))
  if ($posMsg) { [void]$msg.Add($posMsg) }
  [void]$msg.Add(("line_number: {0}" -f $ln))
  [void]$msg.Add("line_text:")
  [void]$msg.Add($lineTxt)

  Write-Utf8NoBomLf $Report (($msg.ToArray()) -join "`n")

  Write-Host "PATCH_FAILED (captured):" -ForegroundColor Red
  Write-Host ("  report: {0}" -f $Report) -ForegroundColor Yellow
  Write-Host ("  line_number: {0}" -f $ln) -ForegroundColor Cyan
  Write-Host ("  line_text: {0}" -f $lineTxt) -ForegroundColor Cyan

  throw
}
