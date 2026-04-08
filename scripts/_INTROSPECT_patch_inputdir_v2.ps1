param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-Gate([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }; $null = [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Path -Encoding UTF8)) }

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die ("MISSING_REPO: " + $RepoRoot) }
$ScriptsDir = Join-Path $RepoRoot "scripts"
$Target = Join-Path $ScriptsDir "_PATCH_tree_transcript_dual_v1.ps1"
if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){ Die ("MISSING_TARGET_PATCH: " + $Target) }

$enc = New-Object System.Text.UTF8Encoding($false)
$txt = [System.IO.File]::ReadAllText($Target,$enc).Replace("`r`n","`n").Replace("`r","`n")
$lines = @($txt -split "`n",-1)

# Parse-gate target (should succeed now that non-ASCII was sanitized).
Parse-Gate $Target

# Report all literal $InputDir lines + 2 lines of context each.
$hits = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  $ln = $lines[$i]
  if($ln -like "*`$InputDir*"){
    [void]$hits.Add(("----- LINE {0:D5} -----" -f ($i+1)))
    $a = [Math]::Max(0,$i-2); $b = [Math]::Min($lines.Count-1,$i+2)
    for($j=$a;$j -le $b;$j++){ [void]$hits.Add(("{0:D5}: {1}" -f ($j+1), $lines[$j])) }
  }
}

# Detect execution patterns that could produce: "The term '$InputDir' is not recognized..."
$dq = [char]34
$sq = [char]39
$patInvokeAny = '^[\t ]*[&.][\t ]*([' + $dq + $sq + ']?)\$InputDir\1([\t ]+|$)'
$patCmdPos    = '^[\t ]*\$InputDir(\s+|$)'
$patAssign    = '^[\t ]*\$InputDir[\t ]*='
$inv = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  $ln = $lines[$i]
  if(($ln -match $patInvokeAny) -or (($ln -match $patCmdPos) -and ($ln -notmatch $patAssign))){
    [void]$inv.Add(("{0:D5}: {1}" -f ($i+1), $ln))
  }
}

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$OutDir = Join-Path $ScriptsDir ("_introspect_inputdir_" + $ts)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$HitsPath = Join-Path $OutDir "inputdir_hits_with_context.txt"
$InvPath  = Join-Path $OutDir "inputdir_invocation_candidates.txt"
Write-Utf8NoBomLf $HitsPath (($hits.ToArray()) -join "`n")
Write-Utf8NoBomLf $InvPath  (($inv.ToArray()) -join "`n")

Write-Host "OK: parse-gated + wrote InputDir reports" -ForegroundColor Green
Write-Host ("target: {0}" -f $Target) -ForegroundColor Cyan
Write-Host ("outdir: {0}" -f $OutDir) -ForegroundColor DarkGray
Write-Host ("hits:   {0}" -f $HitsPath) -ForegroundColor DarkGray
Write-Host ("inv:    {0}" -f $InvPath)  -ForegroundColor DarkGray
Write-Host ("count_hits: {0}" -f $hits.Count) -ForegroundColor Cyan
Write-Host ("count_inv:  {0}" -f $inv.Count)  -ForegroundColor Cyan
