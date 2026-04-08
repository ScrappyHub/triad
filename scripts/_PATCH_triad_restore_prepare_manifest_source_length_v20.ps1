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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v20_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find v17 block start
$begin = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*#\s*v17:\s*plan\s*blocks\s*discovery\b'){ $begin = $i; break }
}
if ($begin -lt 0) { Die "NO_V17_BLOCK_START_FOUND" }

# Find v17 block end (the cleanup line)
$end = -1
for($i=$begin+1;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*Remove-Variable\s+-Name\s+__gotBlocks\b'){ $end = $i; break }
}
if ($end -lt 0) { Die "NO_V17_BLOCK_END_FOUND (Remove-Variable __gotBlocks)" }

$indent = ([regex]::Match($lines[$begin], '^(\s*)')).Groups[1].Value

# v20 replacement block: adds expected.* schema support
$blk = New-Object System.Collections.Generic.List[string]
[void]$blk.Add($indent + '# v20: plan blocks discovery (StrictMode-safe). Accept schema variants:')
[void]$blk.Add($indent + '#   blocks | expected.blocks | expected.plan.blocks | expected.data.blocks | expected.payload.blocks | plan.blocks | data.blocks | payload.blocks')
[void]$blk.Add($indent + '$bs = @()')
[void]$blk.Add($indent + '$__gotBlocks = $false')

# 1) top-level blocks
[void]$blk.Add($indent + 'if (-not $__gotBlocks -and (Get-Member -InputObject $planX -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '  $bs = @(@($planX.blocks))')
[void]$blk.Add($indent + '  $__gotBlocks = $true')
[void]$blk.Add($indent + '}')

# 2) expected.*
[void]$blk.Add($indent + 'if (-not $__gotBlocks -and (Get-Member -InputObject $planX -Name "expected" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '  $__e = $planX.expected')
[void]$blk.Add($indent + '  if ($null -ne $__e) {')
[void]$blk.Add($indent + '    if (-not $__gotBlocks -and (Get-Member -InputObject $__e -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '      $bs = @(@($__e.blocks))')
[void]$blk.Add($indent + '      $__gotBlocks = $true')
[void]$blk.Add($indent + '    }')
[void]$blk.Add($indent + '    if (-not $__gotBlocks -and (Get-Member -InputObject $__e -Name "plan" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '      $__ep = $__e.plan')
[void]$blk.Add($indent + '      if ($null -ne $__ep -and (Get-Member -InputObject $__ep -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '        $bs = @(@($__ep.blocks))')
[void]$blk.Add($indent + '        $__gotBlocks = $true')
[void]$blk.Add($indent + '      }')
[void]$blk.Add($indent + '      Remove-Variable -Name __ep -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '    }')
[void]$blk.Add($indent + '    if (-not $__gotBlocks -and (Get-Member -InputObject $__e -Name "data" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '      $__ed = $__e.data')
[void]$blk.Add($indent + '      if ($null -ne $__ed -and (Get-Member -InputObject $__ed -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '        $bs = @(@($__ed.blocks))')
[void]$blk.Add($indent + '        $__gotBlocks = $true')
[void]$blk.Add($indent + '      }')
[void]$blk.Add($indent + '      Remove-Variable -Name __ed -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '    }')
[void]$blk.Add($indent + '    if (-not $__gotBlocks -and (Get-Member -InputObject $__e -Name "payload" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '      $__eq = $__e.payload')
[void]$blk.Add($indent + '      if ($null -ne $__eq -and (Get-Member -InputObject $__eq -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '        $bs = @(@($__eq.blocks))')
[void]$blk.Add($indent + '        $__gotBlocks = $true')
[void]$blk.Add($indent + '      }')
[void]$blk.Add($indent + '      Remove-Variable -Name __eq -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '    }')
[void]$blk.Add($indent + '  }')
[void]$blk.Add($indent + '  Remove-Variable -Name __e -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '}')

# 3) plan.blocks
[void]$blk.Add($indent + 'if (-not $__gotBlocks -and (Get-Member -InputObject $planX -Name "plan" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '  $__p = $planX.plan')
[void]$blk.Add($indent + '  if ($null -ne $__p -and (Get-Member -InputObject $__p -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '    $bs = @(@($__p.blocks))')
[void]$blk.Add($indent + '    $__gotBlocks = $true')
[void]$blk.Add($indent + '  }')
[void]$blk.Add($indent + '  Remove-Variable -Name __p -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '}')

# 4) data.blocks
[void]$blk.Add($indent + 'if (-not $__gotBlocks -and (Get-Member -InputObject $planX -Name "data" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '  $__d = $planX.data')
[void]$blk.Add($indent + '  if ($null -ne $__d -and (Get-Member -InputObject $__d -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '    $bs = @(@($__d.blocks))')
[void]$blk.Add($indent + '    $__gotBlocks = $true')
[void]$blk.Add($indent + '  }')
[void]$blk.Add($indent + '  Remove-Variable -Name __d -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '}')

# 5) payload.blocks
[void]$blk.Add($indent + 'if (-not $__gotBlocks -and (Get-Member -InputObject $planX -Name "payload" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '  $__q = $planX.payload')
[void]$blk.Add($indent + '  if ($null -ne $__q -and (Get-Member -InputObject $__q -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '    $bs = @(@($__q.blocks))')
[void]$blk.Add($indent + '    $__gotBlocks = $true')
[void]$blk.Add($indent + '  }')
[void]$blk.Add($indent + '  Remove-Variable -Name __q -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '}')

# final decision
[void]$blk.Add($indent + 'if (-not $__gotBlocks) {')
[void]$blk.Add($indent + '  $keys = @(@($planX | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name))')
[void]$blk.Add($indent + '  throw ("PLAN_SCHEMA_NO_BLOCKS keys=" + ($keys -join ","))')
[void]$blk.Add($indent + '}')
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
Write-Host ("FINAL_OK: patched " + $Target + " (replaced v17 block lines " + $begin + ".." + $end + " with v20 expected.blocks resolver)") -ForegroundColor Green
