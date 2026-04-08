param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("MISSING_REPO: " + $RepoRoot) }
$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }

$hits = New-Object System.Collections.Generic.List[object]
$files = Get-ChildItem -LiteralPath $ScriptsDir -File -Filter "*.ps1" -Force
foreach($f in $files){
  $p = $f.FullName
  $raw = Get-Content -Raw -LiteralPath $p -Encoding UTF8
  $txt = $raw.Replace("`r`n","`n").Replace("`r","`n")
  $lines = @(@($txt -split "`n",-1))
  for($i=0;$i -lt $lines.Count;$i++){
    if ($lines[$i] -match '\s-\s*InputFile\b' -or $lines[$i] -match '\s-InputFile\b'){
      $ctxA = [Math]::Max(0,$i-2)
      $ctxB = [Math]::Min($lines.Count-1,$i+2)
      $ctx = ($lines[$ctxA..$ctxB] -join " | ")
      $hits.Add([pscustomobject]@{ file=$p; line=($i+1); text=$lines[$i]; context=$ctx }) | Out-Null
    }
  }
}

Write-Host ("FOUND_INPUTFILE_USES: {0}" -f $hits.Count) -ForegroundColor Yellow
foreach($h in $hits){
  Write-Host ("- {0}:{1}" -f $h.file, $h.line) -ForegroundColor Cyan
  Write-Host ("  " + $h.text) -ForegroundColor Gray
  Write-Host ("  ctx: " + $h.context) -ForegroundColor DarkGray
}

# Emit machine-readable list for next patch stage
$out = Join-Path $ScriptsDir "_work_inputfile_uses_v1.json"
$hits | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("WROTE: " + $out) -ForegroundColor Green
