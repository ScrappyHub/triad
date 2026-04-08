param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("MISSING_REPO: " + $RepoRoot) }

$ScriptsDir = Join-Path $RepoRoot "scripts"
$Target = Join-Path $ScriptsDir "_PATCH_tree_transcript_dual_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_PATCH: " + $Target) }

# Load patch text for context dumping
$enc = New-Object System.Text.UTF8Encoding($false)
$txt = [System.IO.File]::ReadAllText($Target,$enc).Replace("`r`n","`n").Replace("`r","`n")
$lines = @($txt -split "`n",-1)

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$OutDir = Join-Path $ScriptsDir ("_gate1_probe_" + $ts)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Report = Join-Path $OutDir "gate1_report.txt"
$Ctx    = Join-Path $OutDir "fail_context.txt"
$Top    = Join-Path $OutDir "patch_top_120_lines.txt"

# Always write the top of the patch (helps when failure is near start)
$topN = [Math]::Min(120, $lines.Count)
$top = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $topN;$i++){
  [void]$top.Add(("{0:D5}: {1}" -f ($i+1), $lines[$i]))
}
Write-Utf8NoBomLf $Top (($top.ToArray()) -join "`n")

try {
  & $Target -RepoRoot $RepoRoot
  Write-Utf8NoBomLf $Report ("GATE1_OK`npatch: " + $Target + "`nrepo: " + $RepoRoot + "`n")
  Write-Host "GATE1_OK: dual transcript patch ran clean" -ForegroundColor Green
  Write-Host ("outdir: {0}" -f $OutDir) -ForegroundColor DarkGray
}
catch {
  $e = $_.Exception
  $inv = $_.InvocationInfo

  $ln = -1
  $lineTxt = ""
  $scriptName = ""
  $off = 0

  if ($inv) {
    if ($inv.ScriptLineNumber) { $ln = [int]$inv.ScriptLineNumber }
    if ($inv.Line) { $lineTxt = [string]$inv.Line }
    if ($inv.ScriptName) { $scriptName = [string]$inv.ScriptName }
    if ($inv.OffsetInLine) { $off = [int]$inv.OffsetInLine }
  }

  # Context around failing line inside the PATCH file if failure points into it
  $ctx = New-Object System.Collections.Generic.List[string]
  if ($scriptName -and ($scriptName -ieq $Target) -and ($ln -ge 1) -and ($ln -le $lines.Count)) {
    $a = [Math]::Max(1, $ln-8)
    $b = [Math]::Min($lines.Count, $ln+8)
    [void]$ctx.Add(("FAIL_CONTEXT for patch line {0} (offset {1})" -f $ln, $off))
    for($i=$a; $i -le $b; $i++){
      [void]$ctx.Add(("{0:D5}: {1}" -f $i, $lines[$i-1]))
    }
  } else {
    [void]$ctx.Add("FAIL_CONTEXT: failure did not point directly into patch file line numbers.")
    [void]$ctx.Add(("invocation_script: {0}" -f $scriptName))
    [void]$ctx.Add(("invocation_line: {0}" -f $ln))
    [void]$ctx.Add(("invocation_text: {0}" -f $lineTxt))
  }
  Write-Utf8NoBomLf $Ctx (($ctx.ToArray()) -join "`n")

  $msg = New-Object System.Collections.Generic.List[string]
  [void]$msg.Add("GATE1_FAIL")
  [void]$msg.Add(("patch: {0}" -f $Target))
  [void]$msg.Add(("repo:  {0}" -f $RepoRoot))
  [void]$msg.Add(("error_type: {0}" -f $e.GetType().FullName))
  [void]$msg.Add(("message: {0}" -f $e.Message))
  if ($inv) {
    [void]$msg.Add(("invocation_script: {0}" -f $inv.ScriptName))
    [void]$msg.Add(("invocation_pos: {0}:{1}:{2}" -f $inv.ScriptName, $inv.ScriptLineNumber, $inv.OffsetInLine))
    [void]$msg.Add(("invocation_line_text: {0}" -f $inv.Line))
  }
  [void]$msg.Add("script_stack_trace:")
  [void]$msg.Add($_.ScriptStackTrace)

  [void]$msg.Add("")
  [void]$msg.Add("artifacts:")
  [void]$msg.Add(("  report: {0}" -f $Report))
  [void]$msg.Add(("  context: {0}" -f $Ctx))
  [void]$msg.Add(("  patch_top_120: {0}" -f $Top))

  Write-Utf8NoBomLf $Report (($msg.ToArray()) -join "`n")

  Write-Host "GATE1_FAIL (captured):" -ForegroundColor Red
  Write-Host ("outdir: {0}" -f $OutDir) -ForegroundColor Yellow
  Write-Host ("report: {0}" -f $Report) -ForegroundColor Yellow
  Write-Host ("context: {0}" -f $Ctx) -ForegroundColor Yellow
  Write-Host ("patch_top_120: {0}" -f $Top) -ForegroundColor Yellow

  throw
}
