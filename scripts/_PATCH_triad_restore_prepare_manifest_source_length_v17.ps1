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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v17_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find the exact PLAN_NO_BLOCKS_FOR_LEN throw line we inserted in v16
$ix = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)PLAN_NO_BLOCKS_FOR_LEN'){ $ix = $i; break }
}
if ($ix -lt 0) { Die "NO_PLAN_NO_BLOCKS_FOR_LEN_LINE_FOUND (v16 may have drifted)" }

$indent = ([regex]::Match($lines[$ix], '^(\s*)')).Groups[1].Value

# Replace the single line with a robust block that sets $bs and/or $mx deterministically.
$blk = New-Object System.Collections.Generic.List[string]
[void]$blk.Add($indent + '# v17: plan blocks discovery (StrictMode-safe). Accept schema variants: blocks | plan.blocks | data.blocks | payload.blocks')
[void]$blk.Add($indent + '$bs = @()')
[void]$blk.Add($indent + '$__gotBlocks = $false')

# helper: try top-level blocks
[void]$blk.Add($indent + 'if (-not $__gotBlocks -and (Get-Member -InputObject $planX -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '  $bs = @(@($planX.blocks))')
[void]$blk.Add($indent + '  $__gotBlocks = $true')
[void]$blk.Add($indent + '}')

# helper: try plan.blocks
[void]$blk.Add($indent + 'if (-not $__gotBlocks -and (Get-Member -InputObject $planX -Name "plan" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '  $__p = $planX.plan')
[void]$blk.Add($indent + '  if ($null -ne $__p -and (Get-Member -InputObject $__p -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '    $bs = @(@($__p.blocks))')
[void]$blk.Add($indent + '    $__gotBlocks = $true')
[void]$blk.Add($indent + '  }')
[void]$blk.Add($indent + '  Remove-Variable -Name __p -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '}')

# helper: try data.blocks
[void]$blk.Add($indent + 'if (-not $__gotBlocks -and (Get-Member -InputObject $planX -Name "data" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '  $__d = $planX.data')
[void]$blk.Add($indent + '  if ($null -ne $__d -and (Get-Member -InputObject $__d -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '    $bs = @(@($__d.blocks))')
[void]$blk.Add($indent + '    $__gotBlocks = $true')
[void]$blk.Add($indent + '  }')
[void]$blk.Add($indent + '  Remove-Variable -Name __d -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '}')

# helper: try payload.blocks
[void]$blk.Add($indent + 'if (-not $__gotBlocks -and (Get-Member -InputObject $planX -Name "payload" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '  $__q = $planX.payload')
[void]$blk.Add($indent + '  if ($null -ne $__q -and (Get-Member -InputObject $__q -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '    $bs = @(@($__q.blocks))')
[void]$blk.Add($indent + '    $__gotBlocks = $true')
[void]$blk.Add($indent + '  }')
[void]$blk.Add($indent + '  Remove-Variable -Name __q -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '}')

# If still no blocks, allow planX.length fallback, else throw with keys
[void]$blk.Add($indent + 'if (-not $__gotBlocks) {')
[void]$blk.Add($indent + '  if ((Get-Member -InputObject $planX -Name "length" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '    try { [int64]$mx = $planX.length } catch { [int64]$mx = 0 }')
[void]$blk.Add($indent + '    if ($mx -le 0) {')
[void]$blk.Add($indent + '      $keys = @(@($planX | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name))')
[void]$blk.Add($indent + '      throw ("PLAN_SCHEMA_NO_BLOCKS_AND_BAD_LENGTH keys=" + ($keys -join ","))')
[void]$blk.Add($indent + '    }')
[void]$blk.Add($indent + '    # keep $bs empty; later code will use $mx')
[void]$blk.Add($indent + '  } else {')
[void]$blk.Add($indent + '    $keys = @(@($planX | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name))')
[void]$blk.Add($indent + '    throw ("PLAN_SCHEMA_NO_BLOCKS keys=" + ($keys -join ","))')
[void]$blk.Add($indent + '  }')
[void]$blk.Add($indent + '}')
[void]$blk.Add($indent + 'Remove-Variable -Name __gotBlocks -ErrorAction SilentlyContinue')

# Rewrite file: replace the single PLAN_NO_BLOCKS_FOR_LEN line with blk
$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $ix) {
    foreach($ln in $blk){ [void]$out.Add($ln) }
    continue
  }
  [void]$out.Add($lines[$i])
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (replaced PLAN_NO_BLOCKS_FOR_LEN line at index " + $ix + " with v17 schema-tolerant block)") -ForegroundColor Green
