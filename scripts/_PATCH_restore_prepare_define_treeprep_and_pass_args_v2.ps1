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
$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_restore_prepare_treeprep_args_v2_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find first use of $TreePrep (literal) anywhere
$firstUse = -1
for($i=0;$i -lt $lines.Count;$i++){ if ($lines[$i] -match "(?i)\$TreePrep"){ $firstUse=$i; break } }
if ($firstUse -lt 0) { Die "NO_TREEPREP_SYMBOL_FOUND" }

# Is there an assignment to $TreePrep before first use?
$hasAssign = $false
for($i=0;$i -lt $firstUse;$i++){ if ($lines[$i] -match "(?im)^\s*\$TreePrep\s*="){ $hasAssign=$true; break } }

if (-not $hasAssign) {
  # Insert after the first $ScriptsDir assignment if present; else insert near top (after param block if found).
  $ins = -1
  for($i=0;$i -lt $firstUse;$i++){ if ($lines[$i] -match "(?im)^\s*\$ScriptsDir\s*="){ $ins=$i; break } }
  if ($ins -lt 0) {
    # Try to insert after closing paren of param(...) block
    $pStart=-1; $pEnd=-1
    for($i=0;$i -lt $lines.Count;$i++){ if ($lines[$i] -match "^\s*param\s*\("){ $pStart=$i; break } }
    if ($pStart -ge 0) {
      for($i=$pStart+1;$i -lt $lines.Count;$i++){ if ($lines[$i] -match "^\s*\)\s*$"){ $pEnd=$i; break } }
    }
    if ($pEnd -ge 0) { $ins = $pEnd } else { $ins = 0 }
  }
  $indent = ([regex]::Match($lines[$ins], "^(\s*)")).Groups[1].Value
  $assignLine = $indent + '$TreePrep = Join-Path $ScriptsDir "triad_restore_tree_prepare_v1.ps1"'
  $out = New-Object System.Collections.Generic.List[string]
  for($i=0;$i -lt $lines.Count;$i++){
    [void]$out.Add($lines[$i])
    if ($i -eq $ins) { [void]$out.Add($assignLine) }
  }
  $lines = $out.ToArray()
  Write-Host "PATCH_OK: inserted `$TreePrep assignment" -ForegroundColor Green
} else {
  Write-Host "OK: `$TreePrep already assigned" -ForegroundColor Green
}

# Now replace the line that invokes & $TreePrep with a fully-arg call so it cannot prompt.
$hit = -1
for($i=0;$i -lt $lines.Count;$i++){ if ($lines[$i] -match "(?i)&\s*\$TreePrep\b"){ $hit=$i; break } }
if ($hit -lt 0) { Die "NO_TREEPREP_INVOKE_AMP_LINE_FOUND" }
$indent2 = ([regex]::Match($lines[$hit], "^(\s*)")).Groups[1].Value
$lines[$hit] = $indent2 + 'return (& $TreePrep -RepoRoot $RepoRoot -SnapshotDir $SnapshotDir -OutFile $OutFile -ManifestPath $ManifestPath)'
Write-Host ("PATCH_OK: rewrote & `$TreePrep invoke line at index " + $hit) -ForegroundColor Green

$txt2 = ($lines -join "`n")
Write-Utf8NoBomLf $Target $txt2
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target) -ForegroundColor Green
