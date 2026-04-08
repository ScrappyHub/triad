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
$BackupDir = Join-Path $ScriptsDir ("_backup_manifest_compat_v1_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$changed = New-Object System.Collections.Generic.List[string]
$skipped = New-Object System.Collections.Generic.List[string]

foreach($p in $targets){
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $skipped.Add($p + " (missing)") | Out-Null; continue }
  $raw = Get-Content -Raw -LiteralPath $p -Encoding UTF8
  $txt = $raw.Replace("`r`n","`n").Replace("`r","`n")

  # We patch the single line that sets $ManifestPath to snapshot.manifest.json (or equivalent).
  # Anchor: the literal string "snapshot.manifest.json" must exist somewhere in the file.
  $anchor = "snapshot.manifest.json"
  if ($txt -notlike ("*" + $anchor + "*")) { $skipped.Add($p + " (anchor not found: snapshot.manifest.json)") | Out-Null; continue }

  $lines = @(@($txt -split "`n",-1))
  $idx = -1
  for($i=0;$i -lt $lines.Count;$i++){
    if ($lines[$i] -like "*snapshot.manifest.json*") { $idx = $i; break }
  }
  if ($idx -lt 0) { $skipped.Add($p + " (anchor scan fail)") | Out-Null; continue }

  $indent = ([regex]::Match($lines[$idx], '^(\s*)')).Groups[1].Value

  # Replace that single line with a deterministic resolver block.
  $resolver = New-Object System.Collections.Generic.List[string]
  [void]$resolver.Add($indent + "# Manifest resolution (compat v1; deterministic)")
  [void]$resolver.Add($indent + "$SnapshotDir = $SnapshotDir") # no-op to keep context in place

  # NOTE: we cannot reference unknown variable names; instead we splice using the existing line's LHS variable name.
  $lhs = $null
  $m = [regex]::Match($lines[$idx], '^\s*(\$\w+)\s*=\s*Join-Path\s+\$SnapshotDir\s+["']snapshot\.manifest\.json["']\s*$')
  if ($m.Success) { $lhs = $m.Groups[1].Value }
  if (-not $lhs) {
    # fall back: try to extract $VarName on LHS of "="
    $m2 = [regex]::Match($lines[$idx], '^\s*(\$\w+)\s*=')
    if ($m2.Success) { $lhs = $m2.Groups[1].Value }
  }
  if (-not $lhs) { Die ("MANIFEST_COMPAT_V1_CANNOT_DETECT_LHS: " + $p + " line=" + ($idx+1)) }

  $block = New-Object System.Collections.Generic.List[string]
  [void]$block.Add($indent + "# Manifest resolution (compat v1; deterministic)")
  [void]$block.Add($indent + "$lhs" + " = (Join-Path $SnapshotDir ""snapshot.manifest.json"")")
  [void]$block.Add($indent + "if (-not (Test-Path -LiteralPath " + $lhs + " -PathType Leaf)) {")
  [void]$block.Add($indent + "  $alt = (Join-Path $SnapshotDir ""manifest.json"")")
  [void]$block.Add($indent + "  if (Test-Path -LiteralPath $alt -PathType Leaf) {")
  [void]$block.Add($indent + "    " + "$lhs" + " = $alt")
  [void]$block.Add($indent + "  } else {")
  [void]$block.Add($indent + "    $hits = @(@(Get-ChildItem -LiteralPath $SnapshotDir -File -Force -ErrorAction Stop | Where-Object { $_.Name -match 'manifest' -and $_.Name -match '\.json$' } | Sort-Object Name))")
  [void]$block.Add($indent + "    if ($hits.Count -eq 1) {")
  [void]$block.Add($indent + "      " + "$lhs" + " = $hits[0].FullName")
  [void]$block.Add($indent + "    } elseif ($hits.Count -eq 0) {")
  [void]$block.Add($indent + "      Die (""MISSING_MANIFEST_ANY: "" + (Join-Path $SnapshotDir ""snapshot.manifest.json""))")
  [void]$block.Add($indent + "    } else {")
  [void]$block.Add($indent + "      $names = @(@($hits | ForEach-Object { $_.Name }))")
  [void]$block.Add($indent + "      Die (""AMBIGUOUS_MANIFEST: "" + ($names -join "",""))")
  [void]$block.Add($indent + "    }")
  [void]$block.Add($indent + "  }")
  [void]$block.Add($indent + "}")

  # Splice: replace the single anchor line with the block
  $out = New-Object System.Collections.Generic.List[string]
  for($i=0;$i -lt $lines.Count;$i++){
    if ($i -eq $idx) { foreach($b in $block){ [void]$out.Add($b) }; continue }
    [void]$out.Add($lines[$i])
  }
  $txt2 = ($out.ToArray() -join "`n")

  Copy-Item -LiteralPath $p -Destination (Join-Path $BackupDir ((Split-Path -Leaf $p) + ".pre_patch")) -Force
  Write-Utf8NoBomLf $p $txt2
  Parse-GateFile $p
  $changed.Add($p) | Out-Null
  Write-Host ("PATCHED: " + $p) -ForegroundColor Cyan
}

Write-Host ("PATCH_DONE: changed {0} file(s)" -f $changed.Count) -ForegroundColor Green
foreach($c in $changed){ Write-Host ("  CHANGED: " + $c) -ForegroundColor Cyan }
if ($skipped.Count -gt 0) {
  Write-Host ("SKIPPED: {0} item(s)" -f $skipped.Count) -ForegroundColor Yellow
  foreach($s in $skipped){ Write-Host ("  SKIP: " + $s) -ForegroundColor DarkYellow }
}
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray
