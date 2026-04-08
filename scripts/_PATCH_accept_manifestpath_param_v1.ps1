param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  if ([string]::IsNullOrWhiteSpace($Path)) { Die "WRITE_UTF8_PATH_EMPTY" }
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateFile([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }; $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8; $null = [ScriptBlock]::Create($raw) }

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("MISSING_REPO: " + $RepoRoot) }
$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }

$targets = @(
  (Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"),
  (Join-Path $ScriptsDir "triad_restore_tree_prepare_v1.ps1")
)

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_manifestpath_param_v1_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$changed = New-Object System.Collections.Generic.List[string]
$skipped = New-Object System.Collections.Generic.List[string]

foreach($p in $targets){
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $skipped.Add($p + " (missing)") | Out-Null; continue }
  $raw = Get-Content -Raw -LiteralPath $p -Encoding UTF8
  $txt = $raw.Replace("`r`n","`n").Replace("`r","`n")

  # If it already declares $ManifestPath, just parse-gate and continue
  if ($txt -match '(?m)^\s*\[.*\]\s*\$ManifestPath\b' -or $txt -match '(?m)^\s*\[string\]\s*\$ManifestPath\b' -or $txt -match '(?m)^\s*\$ManifestPath\b') {
    Parse-GateFile $p
    Write-Host ("OK: already has ManifestPath param: " + $p) -ForegroundColor Green
    continue
  }

  $lines = @(@($txt -split "`n",-1))
  $start=-1; $end=-1
  for($i=0;$i -lt $lines.Count;$i++){ if ($lines[$i] -match '^\s*param\s*\('){ $start=$i; break } }
  if ($start -lt 0) { $skipped.Add($p + " (no param block)") | Out-Null; continue }
  for($i=$start+1;$i -lt $lines.Count;$i++){ if ($lines[$i] -match '^\s*\)\s*$'){ $end=$i; break } }
  if ($end -lt 0) { $skipped.Add($p + " (param block not closed)") | Out-Null; continue }

  # Find the SnapshotDir param line to anchor insertion
  $idx=-1
  for($i=$start+1;$i -lt $end;$i++){ if ($lines[$i] -match '\$\bSnapshotDir\b'){ $idx=$i; break } }
  if ($idx -lt 0) { $skipped.Add($p + " (no SnapshotDir param line found)") | Out-Null; continue }

  $indent = ([regex]::Match($lines[$idx], '^(\s*)')).Groups[1].Value
  # Ensure SnapshotDir line ends with a comma so we can safely insert a new param after it
  if (-not $lines[$idx].TrimEnd().EndsWith(",")) { $lines[$idx] = $lines[$idx].TrimEnd() + "," }

  $out = New-Object System.Collections.Generic.List[string]
  for($i=0;$i -lt $lines.Count;$i++){
    [void]$out.Add($lines[$i])
    if ($i -eq $idx) { [void]$out.Add($indent + '[string]$ManifestPath,') }
  }
  $txt2 = ($out.ToArray() -join "`n")

  Copy-Item -LiteralPath $p -Destination (Join-Path $BackupDir ((Split-Path -Leaf $p) + ".pre_patch")) -Force
  Write-Utf8NoBomLf $p $txt2
  Parse-GateFile $p
  $changed.Add($p) | Out-Null
  Write-Host ("PATCHED: " + $p + " (added [string]$ManifestPath)") -ForegroundColor Cyan
}

Write-Host ("PATCH_DONE: changed {0} file(s)" -f $changed.Count) -ForegroundColor Green
foreach($c in $changed){ Write-Host ("  CHANGED: " + $c) -ForegroundColor Cyan }
if ($skipped.Count -gt 0) {
  Write-Host ("SKIPPED: {0} item(s)" -f $skipped.Count) -ForegroundColor Yellow
  foreach($s in $skipped){ Write-Host ("  SKIP: " + $s) -ForegroundColor DarkYellow }
}
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray
