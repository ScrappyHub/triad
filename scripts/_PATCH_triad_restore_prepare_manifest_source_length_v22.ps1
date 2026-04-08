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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v22_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find the v21 throw line and replace the whole surrounding if(-not $__gotBlocks){...} with total_bytes fallback.
$ixThrow = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)PLAN_SCHEMA_NO_BLOCKS\s+v21'){ $ixThrow = $i; break }
}
if ($ixThrow -lt 0) { Die "NO_V21_PLAN_SCHEMA_NO_BLOCKS_THROW_FOUND" }

# Find start of the if (-not $__gotBlocks) { that contains this throw
$ixIf = -1
for($i=$ixThrow; $i -ge 0; $i--){
  if ($lines[$i] -match '(?im)^\s*if\s*\(\s*-not\s+\$__gotBlocks\s*\)\s*\{\s*$'){ $ixIf = $i; break }
}
if ($ixIf -lt 0) { Die "NO_V21_IF_NOT_GOTBLOCKS_FOUND" }

# Find matching closing brace for that if-block (simple brace counter within lines)
$depth = 0
$ixEnd = -1
for($i=$ixIf; $i -lt $lines.Count; $i++){
  $ln = $lines[$i]
  $opens = ([regex]::Matches($ln,'\{')).Count
  $closes = ([regex]::Matches($ln,'\}')).Count
  $depth += $opens
  $depth -= $closes
  if ($i -gt $ixIf -and $depth -le 0) { $ixEnd = $i; break }
}
if ($ixEnd -lt 0) { Die "NO_V21_IF_BLOCK_END_FOUND" }

$indent = ([regex]::Match($lines[$ixIf], '^(\s*)')).Groups[1].Value

$blk = New-Object System.Collections.Generic.List[string]
[void]$blk.Add($indent + 'if (-not $__gotBlocks) {')
[void]$blk.Add($indent + '  # v22: no blocks in plan schema; fallback to expected.total_bytes and synthesize a single block.')
[void]$blk.Add($indent + '  [int64]$__tb = 0')
[void]$blk.Add($indent + '  try {')
[void]$blk.Add($indent + '    if ($null -ne $__e1) {')
[void]$blk.Add($indent + '      $pTB = $__e1.PSObject.Properties["total_bytes"]')
[void]$blk.Add($indent + '      if ($null -ne $pTB -and $null -ne $pTB.Value) { $__tb = [int64]$pTB.Value }')
[void]$blk.Add($indent + '    }')
[void]$blk.Add($indent + '  } catch { $__tb = 0 }')
[void]$blk.Add($indent + '  if ($__tb -le 0) {')
[void]$blk.Add($indent + '    $kTop = "<unknown>"; try { $kTop = (@(@($planX | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)) -join ",") } catch { }')
[void]$blk.Add($indent + '    $kExp = "<null>"; $tExp = "<null>"')
[void]$blk.Add($indent + '    try { if ($null -ne $__e1) { $tExp = $__e1.GetType().FullName } } catch { }')
[void]$blk.Add($indent + '    try { if ($null -ne $__e1) { $kExp = (@(@($__e1 | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)) -join ",") } } catch { }')
[void]$blk.Add($indent + '    throw ("PLAN_NO_BLOCKS_AND_NO_TOTAL_BYTES v22 topKeys=" + $kTop + " expectedType=" + $tExp + " expectedKeys=" + $kExp)')
[void]$blk.Add($indent + '  }')
[void]$blk.Add($indent + '  # Synthesize one block so downstream max-end logic works deterministically.')
[void]$blk.Add($indent + '  $b0 = [pscustomobject]@{ offset = [int64]0; length = [int64]$__tb }')
[void]$blk.Add($indent + '  $bs = @($b0)')
[void]$blk.Add($indent + '  $__gotBlocks = $true')
[void]$blk.Add($indent + '  Remove-Variable -Name b0 -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '  Remove-Variable -Name __tb -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '}')

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $ixIf) {
    foreach($ln in $blk){ [void]$out.Add($ln) }
    $i = $ixEnd
    continue
  }
  [void]$out.Add($lines[$i])
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (replaced v21 no-blocks throw block lines " + $ixIf + ".." + $ixEnd + " with v22 total_bytes fallback)") -ForegroundColor Green
