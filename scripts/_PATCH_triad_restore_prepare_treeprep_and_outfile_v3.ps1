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
function Parse-GateFile([string]$Path){
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  $null = [ScriptBlock]::Create($raw)
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v3_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

# --- Patch A: triad_restore_tree_prepare_v1.ps1 accepts -OutFile via Alias on OutDir ---
$TreePrepPath = Join-Path $ScriptsDir "triad_restore_tree_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $TreePrepPath -PathType Leaf)) { Die ("MISSING_TREE_PREP: " + $TreePrepPath) }
Copy-Item -LiteralPath $TreePrepPath -Destination (Join-Path $BackupDir ((Split-Path -Leaf $TreePrepPath) + ".pre_patch")) -Force

$txtA = (Get-Content -Raw -LiteralPath $TreePrepPath -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

if ($txtA -match '(?im)^\s*\[Alias\("OutFile"\)\]\s*$') {
  Parse-GateFile $TreePrepPath
  Write-Host ("OK: tree_prepare already has [Alias(""OutFile"")]: " + $TreePrepPath) -ForegroundColor Green
} else {
  $lines = @(@($txtA -split "`n",-1))
  $start=-1; $end=-1; $idx=-1
  for($i=0;$i -lt $lines.Count;$i++){ if ($lines[$i] -match '(?im)^\s*param\s*\('){ $start=$i; break } }
  if ($start -lt 0) { Die "TREE_PREP_NO_PARAM_BLOCK" }
  for($i=$start+1;$i -lt $lines.Count;$i++){ if ($lines[$i] -match '(?im)^\s*\)\s*$'){ $end=$i; break } }
  if ($end -lt 0) { Die "TREE_PREP_PARAM_BLOCK_NOT_CLOSED" }
  for($i=$start+1;$i -lt $end;$i++){ if ($lines[$i] -match '\$\bOutDir\b'){ $idx=$i; break } }
  if ($idx -lt 0) { Die "TREE_PREP_NO_OUTDIR_PARAM_LINE_FOUND" }

  $indent = ([regex]::Match($lines[$idx], '^(\s*)')).Groups[1].Value
  $out = New-Object System.Collections.Generic.List[string]
  for($i=0;$i -lt $lines.Count;$i++){
    if ($i -eq $idx) { [void]$out.Add($indent + '[Alias("OutFile")]') }
    [void]$out.Add($lines[$i])
  }
  $txt2 = ($out.ToArray() -join "`n")
  Write-Utf8NoBomLf $TreePrepPath $txt2
  Parse-GateFile $TreePrepPath
  Write-Host ("PATCH_OK: added [Alias(""OutFile"")] above OutDir param: " + $TreePrepPath) -ForegroundColor Green
}

# --- Patch B: triad_restore_prepare_v1.ps1 defines $TreePrep and rewrites '& $TreePrep' call to pass args ---
$RestorePrepPath = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $RestorePrepPath -PathType Leaf)) { Die ("MISSING_RESTORE_PREP: " + $RestorePrepPath) }
Copy-Item -LiteralPath $RestorePrepPath -Destination (Join-Path $BackupDir ((Split-Path -Leaf $RestorePrepPath) + ".pre_patch")) -Force

$txtB = (Get-Content -Raw -LiteralPath $RestorePrepPath -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$linesB = @(@($txtB -split "`n",-1))

# Find first $ScriptsDir assignment line
$sd = -1
for($i=0;$i -lt $linesB.Count;$i++){ if ($linesB[$i] -match '(?im)^\s*\$ScriptsDir\s*='){ $sd=$i; break } }
if ($sd -lt 0) { Die "RESTORE_PREP_NO_SCRIPTSDIR_ASSIGN_FOUND" }

# Ensure $TreePrep assignment exists (anywhere)
$hasTP = $false
for($i=0;$i -lt $linesB.Count;$i++){ if ($linesB[$i] -match '(?im)^\s*\$TreePrep\s*='){ $hasTP=$true; break } }

if (-not $hasTP) {
  $indentTP = ([regex]::Match($linesB[$sd], '^(\s*)')).Groups[1].Value
  $assignTP = $indentTP + '$TreePrep = Join-Path $ScriptsDir "triad_restore_tree_prepare_v1.ps1"'
  $outB = New-Object System.Collections.Generic.List[string]
  for($i=0;$i -lt $linesB.Count;$i++){
    [void]$outB.Add($linesB[$i])
    if ($i -eq $sd) { [void]$outB.Add($assignTP) }
  }
  $linesB = $outB.ToArray()
  Write-Host 'PATCH_OK: inserted `$TreePrep assignment after `$ScriptsDir' -ForegroundColor Green
} else {
  Write-Host 'OK: `$TreePrep already assigned in restore_prepare' -ForegroundColor Green
}

# Rewrite the first line that invokes: & $TreePrep  (to prevent interactive prompting)
$hit = -1
for($i=0;$i -lt $linesB.Count;$i++){ if ($linesB[$i] -match '(?i)&\s*\$TreePrep\b'){ $hit=$i; break } }
if ($hit -lt 0) { Die "RESTORE_PREP_NO_AMP_TREEPREP_LINE_FOUND" }

$indentCall = ([regex]::Match($linesB[$hit], '^(\s*)')).Groups[1].Value
$linesB[$hit] = $indentCall + 'return (& $TreePrep -RepoRoot $RepoRoot -SnapshotDir $SnapshotDir -OutFile $OutFile -ManifestPath $ManifestPath)'
Write-Host ("PATCH_OK: rewrote & `$TreePrep invoke line at index " + $hit) -ForegroundColor Green

$finalB = ($linesB -join "`n")
Write-Utf8NoBomLf $RestorePrepPath $finalB
Parse-GateFile $RestorePrepPath
Write-Host ("FINAL_OK: patched " + $RestorePrepPath) -ForegroundColor Green
