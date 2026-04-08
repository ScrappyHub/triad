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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v4_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$RestorePrepPath = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $RestorePrepPath -PathType Leaf)) { Die ("MISSING_RESTORE_PREP: " + $RestorePrepPath) }
Copy-Item -LiteralPath $RestorePrepPath -Destination (Join-Path $BackupDir ((Split-Path -Leaf $RestorePrepPath) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $RestorePrepPath -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Injection point:
# Prefer right after Set-StrictMode. Else after param(...) block. Else top of file.
$ins = -1
for($i=0;$i -lt $lines.Count;$i++){ if ($lines[$i] -match '(?im)^\s*Set-StrictMode\b'){ $ins=$i+1; break } }
if ($ins -lt 0) {
  $p=-1; $pend=-1
  for($i=0;$i -lt $lines.Count;$i++){ if ($lines[$i] -match '(?im)^\s*param\s*\('){ $p=$i; break } }
  if ($p -ge 0) {
    for($i=$p+1;$i -lt $lines.Count;$i++){ if ($lines[$i] -match '(?im)^\s*\)\s*$'){ $pend=$i; break } }
    if ($pend -ge 0) { $ins = $pend + 1 }
  }
}
if ($ins -lt 0) { $ins = 0 }

# Detect existing assigns
$hasScriptsDir = $false
$hasTreePrep = $false
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*\$ScriptsDir\s*='){ $hasScriptsDir=$true }
  if ($lines[$i] -match '(?im)^\s*\$TreePrep\s*='){ $hasTreePrep=$true }
}

# Build injection block (guarded; PSScriptRoot is stable)
$inj = New-Object System.Collections.Generic.List[string]
[void]$inj.Add('# --- injected by _PATCH_triad_restore_prepare_treeprep_root_v4.ps1 ---')
if (-not $hasScriptsDir) {
  [void]$inj.Add('if (-not (Get-Variable -Name ScriptsDir -Scope Local -ErrorAction SilentlyContinue)) {')
  [void]$inj.Add('  $ScriptsDir = $PSScriptRoot')
  [void]$inj.Add('}')
} else {
  [void]$inj.Add('# (ScriptsDir already assigned in this file)')
}
if (-not $hasTreePrep) {
  [void]$inj.Add('if (-not (Get-Variable -Name TreePrep -Scope Local -ErrorAction SilentlyContinue)) {')
  [void]$inj.Add('  $TreePrep = Join-Path $ScriptsDir "triad_restore_tree_prepare_v1.ps1"')
  [void]$inj.Add('}')
} else {
  [void]$inj.Add('# (TreePrep already assigned in this file)')
}
[void]$inj.Add('# --- end injected block ---')

# Insert injection block
$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $ins) {
    foreach($ln in $inj){ [void]$out.Add($ln) }
    [void]$out.Add('')
  }
  [void]$out.Add($lines[$i])
}
$lines2 = $out.ToArray()

# Rewrite first "& $TreePrep" invocation (ensure no prompting)
$hit = -1
for($i=0;$i -lt $lines2.Count;$i++){ if ($lines2[$i] -match '(?i)&\s*\$TreePrep\b'){ $hit=$i; break } }
if ($hit -lt 0) { Die "RESTORE_PREP_NO_AMP_TREEPREP_LINE_FOUND" }

$indent = ([regex]::Match($lines2[$hit], '^(\s*)')).Groups[1].Value
$lines2[$hit] = $indent + 'return (& $TreePrep -RepoRoot $RepoRoot -SnapshotDir $SnapshotDir -OutFile $OutFile -ManifestPath $ManifestPath)'
Write-Host ("PATCH_OK: rewrote & `$TreePrep invoke line at index " + $hit) -ForegroundColor Green

$final = ($lines2 -join "`n")
Write-Utf8NoBomLf $RestorePrepPath $final
Parse-GateFile $RestorePrepPath
Write-Host ("FINAL_OK: patched " + $RestorePrepPath) -ForegroundColor Green
