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
function Parse-GateFile([string]$Path){ $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8; $null = [ScriptBlock]::Create($raw) }

$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }
$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_fix_dispatch_and_outfile_v2_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$TreePrep = Join-Path $ScriptsDir "triad_restore_tree_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $TreePrep -PathType Leaf)) { Die ("MISSING_TREE_PREP: " + $TreePrep) }
Copy-Item -LiteralPath $TreePrep -Destination (Join-Path $BackupDir ((Split-Path -Leaf $TreePrep) + ".pre_patch")) -Force
$txt = (Get-Content -Raw -LiteralPath $TreePrep -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

# If alias already present, skip
if ($txt -match '(?im)^\s*\[Alias\("OutFile"\)\]\s*$') {
  Parse-GateFile $TreePrep
  Write-Host ("OK: tree_prepare already accepts -OutFile: " + $TreePrep) -ForegroundColor Green
} else {
  $lines = @(@($txt -split "`n",-1))
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
  Write-Utf8NoBomLf $TreePrep $txt2
  Parse-GateFile $TreePrep
  Write-Host ("PATCH_OK: added [Alias(""OutFile"")] above OutDir param: " + $TreePrep) -ForegroundColor Green
}

$RestorePrep = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $RestorePrep -PathType Leaf)) { Die ("MISSING_RESTORE_PREP: " + $RestorePrep) }
Copy-Item -LiteralPath $RestorePrep -Destination (Join-Path $BackupDir ((Split-Path -Leaf $RestorePrep) + ".pre_patch")) -Force
$txt = (Get-Content -Raw -LiteralPath $RestorePrep -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))
$hit=-1
for($i=0;$i -lt $lines.Count;$i++){ if ($lines[$i] -match 'triad_restore_tree_prepare_v1\.ps1'){ $hit=$i; break } }
if ($hit -lt 0) { Die "RESTORE_PREP_NO_TREE_PREP_INVOKE_LINE_FOUND" }
$indent = ([regex]::Match($lines[$hit], '^(\s*)')).Groups[1].Value
$lines[$hit] = $indent + 'return (& (Join-Path $ScriptsDir "triad_restore_tree_prepare_v1.ps1") -RepoRoot $RepoRoot -SnapshotDir $SnapshotDir -OutFile $OutFile -ManifestPath $ManifestPath)'
$txt2 = ($lines -join "`n")
Write-Utf8NoBomLf $RestorePrep $txt2
Parse-GateFile $RestorePrep
Write-Host ("PATCH_OK: restore_prepare tree dispatch now passes args via inline Join-Path: " + $RestorePrep) -ForegroundColor Green

