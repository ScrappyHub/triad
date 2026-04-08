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

$enc = New-Object System.Text.UTF8Encoding($false)
$txt = [System.IO.File]::ReadAllText($Target,$enc).Replace("`r`n","`n").Replace("`r","`n")
$lines = @($txt -split "`n",-1)

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$OutDir = Join-Path $ScriptsDir ("_introspect_inputdir_escaped_" + $ts)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$HitsAll   = New-Object System.Collections.Generic.List[string]
$HitsEsc   = New-Object System.Collections.Generic.List[string]
$HitsCall  = New-Object System.Collections.Generic.List[string]

# Patterns (ASCII-only):
#  - any literal "$InputDir" occurrences (already known, but we keep it)
#  - backtick-escaped "`$InputDir"
#  - likely call operator invocations containing InputDir (various quoting/parens)
$patAny  = '\$InputDir'
$patEsc  = '`\$InputDir'
$patCall = '^[\t ]*[&.][\t ]*[\(\s]*["'']?`?\$InputDir'

for($i=0;$i -lt $lines.Count;$i++){
  $ln = [string]$lines[$i]
  if ($ln -match $patAny)  { [void]$HitsAll.Add(("{0:D5}: {1}" -f ($i+1), $ln)) }
  if ($ln -match $patEsc)  { [void]$HitsEsc.Add(("{0:D5}: {1}" -f ($i+1), $ln)) }
  if ($ln -match $patCall) { [void]$HitsCall.Add(("{0:D5}: {1}" -f ($i+1), $ln)) }
}

$AllPath  = Join-Path $OutDir "hits_any_InputDir.txt"
$EscPath  = Join-Path $OutDir "hits_escaped_backtick_InputDir.txt"
$CallPath = Join-Path $OutDir "hits_probable_call_operator_InputDir.txt"

Write-Utf8NoBomLf $AllPath  (($HitsAll.ToArray())  -join "`n")
Write-Utf8NoBomLf $EscPath  (($HitsEsc.ToArray())  -join "`n")
Write-Utf8NoBomLf $CallPath (($HitsCall.ToArray()) -join "`n")

Write-Host "OK: wrote InputDir hit reports" -ForegroundColor Green
Write-Host ("outdir: {0}" -f $OutDir) -ForegroundColor DarkGray
Write-Host ("any:    {0} (count={1})" -f $AllPath,  $HitsAll.Count)  -ForegroundColor Cyan
Write-Host ("esc:    {0} (count={1})" -f $EscPath,  $HitsEsc.Count)  -ForegroundColor Cyan
Write-Host ("call:   {0} (count={1})" -f $CallPath, $HitsCall.Count) -ForegroundColor Cyan
