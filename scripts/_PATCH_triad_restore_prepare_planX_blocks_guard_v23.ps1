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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v23_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find the exact offending line(s): $bs = @(@($planX.blocks))
$hits = New-Object System.Collections.Generic.List[int]
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*\$bs\s*=\s*@\(@\(\$planX\.blocks\)\)\s*$') { [void]$hits.Add($i) }
}
if ($hits.Count -lt 1) { Die "NO_PLANX_BLOCKS_ASSIGN_LINE_FOUND" }

# Replace ALL occurrences deterministically (safe/idempotent)
for($h=0;$h -lt $hits.Count;$h++){
  $ix = $hits[$h]
  $indent = ([regex]::Match($lines[$ix], '^(\s*)')).Groups[1].Value

  $blk = New-Object System.Collections.Generic.List[string]
  [void]$blk.Add($indent + '# PATCH_PLANX_BLOCKS_GUARD_V23')
  [void]$blk.Add($indent + '$__mBlocks = (Get-Member -InputObject $planX -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)')
  [void]$blk.Add($indent + 'if ($__mBlocks) {')
  [void]$blk.Add($indent + '  $bs = @(@($planX.blocks))')
  [void]$blk.Add($indent + '} else {')
  [void]$blk.Add($indent + '  # Prefer existing $bs if present; else fall back to expected.total_bytes with a single synthetic block.')
  [void]$blk.Add($indent + '  $__bsVar = Get-Variable -Name bs -Scope Local -ErrorAction SilentlyContinue')
  [void]$blk.Add($indent + '  $__ok = $false')
  [void]$blk.Add($indent + '  if ($null -ne $__bsVar -and $null -ne $__bsVar.Value) {')
  [void]$blk.Add($indent + '    try {')
  [void]$blk.Add($indent + '      $tmp = @(@($__bsVar.Value))')
  [void]$blk.Add($indent + '      if ($tmp.Count -gt 0) { $bs = $tmp; $__ok = $true }')
  [void]$blk.Add($indent + '    } catch { }')
  [void]$blk.Add($indent + '  }')
  [void]$blk.Add($indent + '  if (-not $__ok) {')
  [void]$blk.Add($indent + '    [int64]$__tb = 0')
  [void]$blk.Add($indent + '    try {')
  [void]$blk.Add($indent + '      $e = $null; try { $e = $planX.expected } catch { $e = $null }')
  [void]$blk.Add($indent + '      if ($null -ne $e) {')
  [void]$blk.Add($indent + '        $pTB = $e.PSObject.Properties["total_bytes"]')
  [void]$blk.Add($indent + '        if ($null -ne $pTB -and $null -ne $pTB.Value) { $__tb = [int64]$pTB.Value }')
  [void]$blk.Add($indent + '      }')
  [void]$blk.Add($indent + '    } catch { $__tb = 0 }')
  [void]$blk.Add($indent + '    if ($__tb -le 0) { throw "PLAN_BLOCKS_MISSING_AND_NO_TOTAL_BYTES_V23" }')
  [void]$blk.Add($indent + '    $b0 = [pscustomobject]@{ offset = [int64]0; length = [int64]$__tb }')
  [void]$blk.Add($indent + '    $bs = @($b0)')
  [void]$blk.Add($indent + '    Remove-Variable -Name b0 -ErrorAction SilentlyContinue')
  [void]$blk.Add($indent + '    Remove-Variable -Name __tb -ErrorAction SilentlyContinue')
  [void]$blk.Add($indent + '  }')
  [void]$blk.Add($indent + '  Remove-Variable -Name __ok -ErrorAction SilentlyContinue')
  [void]$blk.Add($indent + '  Remove-Variable -Name __bsVar -ErrorAction SilentlyContinue')
  [void]$blk.Add($indent + '}')
  [void]$blk.Add($indent + 'Remove-Variable -Name __mBlocks -ErrorAction SilentlyContinue')

  # splice replacement in-place: replace single line with multi-line block
  $pre = @()
  if ($ix -gt 0) { $pre = $lines[0..($ix-1)] }
  $post = @()
  if ($ix -lt ($lines.Count-1)) { $post = $lines[($ix+1)..($lines.Count-1)] }
  $lines = @(@($pre) + @($blk.ToArray()) + @($post))

  # adjust subsequent hit indices (because we changed line count)
  $delta = ($blk.Count - 1)
  for($k=$h+1; $k -lt $hits.Count; $k++){
    $hits[$k] = $hits[$k] + $delta
  }
}

$final = ($lines -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (guarded planX.blocks assignment; hits=" + $hits.Count + ")") -ForegroundColor Green
