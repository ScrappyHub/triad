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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v21_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find v20 block start and end (replace entire block)
$begin = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*#\s*v20:\s*plan\s*blocks\s*discovery\b'){ $begin = $i; break }
}
if ($begin -lt 0) { Die "NO_V20_BLOCK_START_FOUND" }

$end = -1
for($i=$begin+1;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*Remove-Variable\s+-Name\s+__gotBlocks\b'){ $end = $i; break }
}
if ($end -lt 0) { Die "NO_V20_BLOCK_END_FOUND (Remove-Variable __gotBlocks)" }

$indent = ([regex]::Match($lines[$begin], '^(\s*)')).Groups[1].Value

$blk = New-Object System.Collections.Generic.List[string]
[void]$blk.Add($indent + '# v21: plan blocks discovery (StrictMode-safe). Handles PSCustomObject + IDictionary/Hashtable.')
[void]$blk.Add($indent + '# Searches roots: planX, planX.expected, planX.expected.expected; then paths: blocks | plan.blocks | data.blocks | payload.blocks')
[void]$blk.Add($indent + '$bs = @()')
[void]$blk.Add($indent + '$__gotBlocks = $false')

# local helpers (inside function scope)
[void]$blk.Add($indent + 'function __Has([object]$o,[string]$n){')
[void]$blk.Add($indent + '  if ($null -eq $o) { return $false }')
[void]$blk.Add($indent + '  if ($o -is [System.Collections.IDictionary]) { return $o.Contains($n) }')
[void]$blk.Add($indent + '  $p = $o.PSObject.Properties[$n]')
[void]$blk.Add($indent + '  return ($null -ne $p)')
[void]$blk.Add($indent + '}')
[void]$blk.Add($indent + 'function __Get([object]$o,[string]$n){')
[void]$blk.Add($indent + '  if ($null -eq $o) { return $null }')
[void]$blk.Add($indent + '  if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] } else { return $null } }')
[void]$blk.Add($indent + '  $p = $o.PSObject.Properties[$n]')
[void]$blk.Add($indent + '  if ($null -ne $p) { return $p.Value }')
[void]$blk.Add($indent + '  return $null')
[void]$blk.Add($indent + '}')

# build candidate roots
[void]$blk.Add($indent + '$__roots = New-Object System.Collections.Generic.List[object]')
[void]$blk.Add($indent + '[void]$__roots.Add($planX)')
[void]$blk.Add($indent + '$__e1 = $null')
[void]$blk.Add($indent + 'if (__Has $planX "expected") { $__e1 = (__Get $planX "expected") }')
[void]$blk.Add($indent + 'if ($null -ne $__e1) { [void]$__roots.Add($__e1) }')
[void]$blk.Add($indent + '$__e2 = $null')
[void]$blk.Add($indent + 'if ($null -ne $__e1 -and (__Has $__e1 "expected")) { $__e2 = (__Get $__e1 "expected") }')
[void]$blk.Add($indent + 'if ($null -ne $__e2) { [void]$__roots.Add($__e2) }')

# try all roots + all paths
[void]$blk.Add($indent + 'for($ri=0; $ri -lt $__roots.Count -and (-not $__gotBlocks); $ri++){')
[void]$blk.Add($indent + '  $__r = $__roots[$ri]')
[void]$blk.Add($indent + '  if ($null -eq $__r) { continue }')

[void]$blk.Add($indent + '  if (-not $__gotBlocks -and (__Has $__r "blocks")) {')
[void]$blk.Add($indent + '    $bs = @(@(__Get $__r "blocks"))')
[void]$blk.Add($indent + '    $__gotBlocks = $true')
[void]$blk.Add($indent + '  }')

[void]$blk.Add($indent + '  if (-not $__gotBlocks -and (__Has $__r "plan")) {')
[void]$blk.Add($indent + '    $__p = (__Get $__r "plan")')
[void]$blk.Add($indent + '    if ($null -ne $__p -and (__Has $__p "blocks")) { $bs = @(@(__Get $__p "blocks")); $__gotBlocks=$true }')
[void]$blk.Add($indent + '    Remove-Variable -Name __p -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '  }')

[void]$blk.Add($indent + '  if (-not $__gotBlocks -and (__Has $__r "data")) {')
[void]$blk.Add($indent + '    $__d = (__Get $__r "data")')
[void]$blk.Add($indent + '    if ($null -ne $__d -and (__Has $__d "blocks")) { $bs = @(@(__Get $__d "blocks")); $__gotBlocks=$true }')
[void]$blk.Add($indent + '    Remove-Variable -Name __d -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '  }')

[void]$blk.Add($indent + '  if (-not $__gotBlocks -and (__Has $__r "payload")) {')
[void]$blk.Add($indent + '    $__q = (__Get $__r "payload")')
[void]$blk.Add($indent + '    if ($null -ne $__q -and (__Has $__q "blocks")) { $bs = @(@(__Get $__q "blocks")); $__gotBlocks=$true }')
[void]$blk.Add($indent + '    Remove-Variable -Name __q -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '  }')

[void]$blk.Add($indent + '  Remove-Variable -Name __r -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '}')

# if still none, print expected type+keys and throw
[void]$blk.Add($indent + 'if (-not $__gotBlocks) {')
[void]$blk.Add($indent + '  $kTop = "<unknown>"')
[void]$blk.Add($indent + '  try { $kTop = (@(@($planX | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)) -join ",") } catch { }')
[void]$blk.Add($indent + '  $kExp = "<null>"')
[void]$blk.Add($indent + '  $tExp = "<null>"')
[void]$blk.Add($indent + '  try { if ($null -ne $__e1) { $tExp = $__e1.GetType().FullName } } catch { }')
[void]$blk.Add($indent + '  try {')
[void]$blk.Add($indent + '    if ($null -ne $__e1) {')
[void]$blk.Add($indent + '      if ($__e1 -is [System.Collections.IDictionary]) { $kExp = (@(@($__e1.Keys)) -join ",") }')
[void]$blk.Add($indent + '      else { $kExp = (@(@($__e1 | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)) -join ",") }')
[void]$blk.Add($indent + '    }')
[void]$blk.Add($indent + '  } catch { }')
[void]$blk.Add($indent + '  throw ("PLAN_SCHEMA_NO_BLOCKS v21 topKeys=" + $kTop + " expectedType=" + $tExp + " expectedKeys=" + $kExp)')
[void]$blk.Add($indent + '}')

# cleanup
[void]$blk.Add($indent + 'Remove-Variable -Name __e1 -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + 'Remove-Variable -Name __e2 -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + 'Remove-Variable -Name __roots -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + 'Remove-Item function:\__Has -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + 'Remove-Item function:\__Get -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + 'Remove-Variable -Name __gotBlocks -ErrorAction SilentlyContinue')

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $begin) {
    foreach($ln in $blk){ [void]$out.Add($ln) }
    $i = $end
    continue
  }
  [void]$out.Add($lines[$i])
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (replaced v20 block lines " + $begin + ".." + $end + " with v21 IDictionary-aware resolver)") -ForegroundColor Green
