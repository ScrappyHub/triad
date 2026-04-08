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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v32_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Locate the v31 replacement block by marker
$mark = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*#\s*PATCH_EXPECTEDROOT_GUARD_V31\s*$'){ $mark = $i; break }
}
if ($mark -lt 0) { Die "NO_V31_EXPECTEDROOT_MARKER_FOUND" }

# Replace from the marker through the cleanup lines (best-effort end: last Remove-Variable -Name pBr2)
$end = -1
for($i=$mark; $i -lt [Math]::Min($mark+80,$lines.Count); $i++){
  if ($lines[$i] -match '(?im)^\s*Remove-Variable\s+-Name\s+pBr2\b'){ $end = $i; break }
}
if ($end -lt 0) { Die "NO_V31_BLOCK_END_FOUND" }

$indent = ([regex]::Match($lines[$mark], '^(\s*)')).Groups[1].Value

$rep = New-Object System.Collections.Generic.List[string]
[void]$rep.Add($indent + '# PATCH_EXPECTEDROOT_GUARD_V32')
[void]$rep.Add($indent + '$expectedRoot = ""')

# 1) manifest.roots.block_root
[void]$rep.Add($indent + 'try {')
[void]$rep.Add($indent + '  $pRoots = $man.PSObject.Properties["roots"]')
[void]$rep.Add($indent + '  if ($null -ne $pRoots -and $null -ne $pRoots.Value) {')
[void]$rep.Add($indent + '    $r = $pRoots.Value')
[void]$rep.Add($indent + '    $pBr = $r.PSObject.Properties["block_root"]')
[void]$rep.Add($indent + '    if ($null -ne $pBr -and $null -ne $pBr.Value) { $expectedRoot = [string]$pBr.Value }')
[void]$rep.Add($indent + '  }')
[void]$rep.Add($indent + '} catch { $expectedRoot = "" }')

# 2) manifest.block_root
[void]$rep.Add($indent + 'if (-not $expectedRoot) {')
[void]$rep.Add($indent + '  try {')
[void]$rep.Add($indent + '    $pBr2 = $man.PSObject.Properties["block_root"]')
[void]$rep.Add($indent + '    if ($null -ne $pBr2 -and $null -ne $pBr2.Value) { $expectedRoot = [string]$pBr2.Value }')
[void]$rep.Add($indent + '  } catch { $expectedRoot = "" }')
[void]$rep.Add($indent + '}')

# 3) planX.roots.block_root
[void]$rep.Add($indent + 'if (-not $expectedRoot) {')
[void]$rep.Add($indent + '  try {')
[void]$rep.Add($indent + '    $pPRoots = $planX.PSObject.Properties["roots"]')
[void]$rep.Add($indent + '    if ($null -ne $pPRoots -and $null -ne $pPRoots.Value) {')
[void]$rep.Add($indent + '      $rr = $pPRoots.Value')
[void]$rep.Add($indent + '      $pPBr = $rr.PSObject.Properties["block_root"]')
[void]$rep.Add($indent + '      if ($null -ne $pPBr -and $null -ne $pPBr.Value) { $expectedRoot = [string]$pPBr.Value }')
[void]$rep.Add($indent + '    }')
[void]$rep.Add($indent + '  } catch { $expectedRoot = "" }')
[void]$rep.Add($indent + '}')

# 4) planX.block_root
[void]$rep.Add($indent + 'if (-not $expectedRoot) {')
[void]$rep.Add($indent + '  try {')
[void]$rep.Add($indent + '    $pPBr2 = $planX.PSObject.Properties["block_root"]')
[void]$rep.Add($indent + '    if ($null -ne $pPBr2 -and $null -ne $pPBr2.Value) { $expectedRoot = [string]$pPBr2.Value }')
[void]$rep.Add($indent + '  } catch { $expectedRoot = "" }')
[void]$rep.Add($indent + '}')

[void]$rep.Add($indent + 'if (-not $expectedRoot) { throw "MISSING_BLOCK_ROOT_V32" }')

# cleanup (StrictMode-safe)
[void]$rep.Add($indent + 'Remove-Variable -Name pRoots -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + 'Remove-Variable -Name r -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + 'Remove-Variable -Name pBr -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + 'Remove-Variable -Name pBr2 -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + 'Remove-Variable -Name pPRoots -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + 'Remove-Variable -Name rr -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + 'Remove-Variable -Name pPBr -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + 'Remove-Variable -Name pPBr2 -ErrorAction SilentlyContinue')

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $mark) {
    foreach($ln in $rep){ [void]$out.Add($ln) }
    $i = $end
    continue
  }
  [void]$out.Add($lines[$i])
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v32 expectedRoot fallback to planX; replaced lines " + $mark + ".." + $end + ")") -ForegroundColor Green
