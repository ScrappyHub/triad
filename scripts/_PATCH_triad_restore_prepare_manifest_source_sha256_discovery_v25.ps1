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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v25_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find v24 block anchor start
$begin = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*#\s*PATCH_MAN_SOURCE_SHA256_GUARD_V24\s*$'){ $begin = $i; break }
}
if ($begin -lt 0) { Die "NO_V24_SHA256_BLOCK_FOUND" }

# Find the specific throw line we want to eliminate
$throwIx = -1
for($i=$begin; $i -lt [Math]::Min($begin+200,$lines.Count); $i++){
  if ($lines[$i] -match '(?im)SOURCE_PATH_DISCOVERY_FAILED_FOR_SHA256_V24'){ $throwIx = $i; break }
}
if ($throwIx -lt 0) { Die "NO_V24_THROW_LINE_FOUND" }

# We replace the whole discovery segment starting at "$candNames = @(" and ending at the throw line.
$segStart = -1
for($i=$begin; $i -lt $throwIx; $i++){
  if ($lines[$i] -match '(?im)^\s*\$candNames\s*=\s*@\('){ $segStart = $i; break }
}
if ($segStart -lt 0) { Die "NO_V24_DISCOVERY_SEGMENT_START_FOUND" }

$indent = ([regex]::Match($lines[$segStart], '^(\s*)')).Groups[1].Value

$rep = New-Object System.Collections.Generic.List[string]
[void]$rep.Add($indent + '# v25: source path discovery (prefer manifest; else derive from OutFile directory)')
[void]$rep.Add($indent + '$__src = $null')

# 1) man.source.path if present
[void]$rep.Add($indent + 'try {')
[void]$rep.Add($indent + '  $p = $man.source.PSObject.Properties["path"]')
[void]$rep.Add($indent + '  if ($null -ne $p -and $null -ne $p.Value) {')
[void]$rep.Add($indent + '    $pp = [string]$p.Value')
[void]$rep.Add($indent + '    if ($pp -and (Test-Path -LiteralPath $pp -PathType Leaf)) { $__src = $pp }')
[void]$rep.Add($indent + '  }')
[void]$rep.Add($indent + '} catch { }')

# 2) man.source.name relative to OutFile directory
[void]$rep.Add($indent + 'if ($null -eq $__src) {')
[void]$rep.Add($indent + '  try {')
[void]$rep.Add($indent + '    $n = $man.source.PSObject.Properties["name"]')
[void]$rep.Add($indent + '    if ($null -ne $n -and $null -ne $n.Value) {')
[void]$rep.Add($indent + '      $nm = [string]$n.Value')
[void]$rep.Add($indent + '      if ($nm) {')
[void]$rep.Add($indent + '        $parent = Split-Path -Parent $OutFile')
[void]$rep.Add($indent + '        $cand2 = Join-Path $parent $nm')
[void]$rep.Add($indent + '        if (Test-Path -LiteralPath $cand2 -PathType Leaf) { $__src = $cand2 }')
[void]$rep.Add($indent + '      }')
[void]$rep.Add($indent + '    }')
[void]$rep.Add($indent + '  } catch { }')
[void]$rep.Add($indent + '}')

# 3) folder scan near OutFile (restorewf folder)
[void]$rep.Add($indent + 'if ($null -eq $__src) {')
[void]$rep.Add($indent + '  $parent = Split-Path -Parent $OutFile')
[void]$rep.Add($indent + '  $leaf = Split-Path -Leaf $OutFile')
[void]$rep.Add($indent + '  # Prefer exact OutFile if it exists as a real file (some pipelines keep it).')
[void]$rep.Add($indent + '  if (Test-Path -LiteralPath $OutFile -PathType Leaf) { $__src = $OutFile }')
[void]$rep.Add($indent + '  if ($null -eq $__src) {')
[void]$rep.Add($indent + '    # Find candidates: same base leaf, but exclude plan/tmp json artifacts.')
[void]$rep.Add($indent + '    $items = Get-ChildItem -LiteralPath $parent -File -ErrorAction Stop | Where-Object {')
[void]$rep.Add($indent + '      $_.Name -like ($leaf + "*") -and')
[void]$rep.Add($indent + '      $_.Name -notlike ($leaf + ".triad_plan_tree_v1_*") -and')
[void]$rep.Add($indent + '      $_.Name -notlike ($leaf + ".triad_tmp_tree_v1_*")')
[void]$rep.Add($indent + '    } | Sort-Object LastWriteTimeUtc -Descending')
[void]$rep.Add($indent + '    if ($items -and $items.Count -ge 1) { $__src = $items[0].FullName }')
[void]$rep.Add($indent + '  }')
[void]$rep.Add($indent + '}')

[void]$rep.Add($indent + 'if ($null -eq $__src) {')
[void]$rep.Add($indent + '  throw ("SOURCE_PATH_DISCOVERY_FAILED_FOR_SHA256_V25 outDir=" + (Split-Path -Parent $OutFile))')
[void]$rep.Add($indent + '}')

# Now splice: keep everything before segStart, insert rep, then keep everything after throwIx
$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $segStart) {
    foreach($ln in $rep){ [void]$out.Add($ln) }
    $i = $throwIx
    continue
  }
  [void]$out.Add($lines[$i])
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v25 sha256 source discovery; replaced lines " + $segStart + ".." + $throwIx + ")") -ForegroundColor Green
