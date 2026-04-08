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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v14_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
if ($txt -match '(?im)^\s*#\s*PATCH_MAN_SOURCE_LEN_V14\s*$') {
  Parse-GateFile $Target
  Write-Host ("OK: v14 already present: " + $Target) -ForegroundColor Green
  return
}

$lines = @(@($txt -split "`n",-1))

# Find exact failing line:
$ix = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*\$expectedLen\s*=\s*\[int64\]\$man\.source\.length\s*$') { $ix = $i; break }
}
if ($ix -lt 0) { Die "NO_EXPECTEDLEN_MAN_SOURCE_LENGTH_LINE_FOUND" }

$indent = ([regex]::Match($lines[$ix], '^(\s*)')).Groups[1].Value

$blk = New-Object System.Collections.Generic.List[string]
[void]$blk.Add($indent + '# PATCH_MAN_SOURCE_LEN_V14')
[void]$blk.Add($indent + '# Ensure $man.source.length exists (bytes). Fallback: plan length.')
[void]$blk.Add($indent + 'if ($null -eq $man) { throw "MANIFEST_NULL" }')

# Ensure man.source exists
[void]$blk.Add($indent + 'if (-not (Get-Member -InputObject $man -Name "source" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '  $src0 = New-Object PSObject')
[void]$blk.Add($indent + '  $man | Add-Member -MemberType NoteProperty -Name "source" -Value $src0 -Force')
[void]$blk.Add($indent + '}')
[void]$blk.Add($indent + 'if ($null -eq $man.source) {')
[void]$blk.Add($indent + '  $src1 = New-Object PSObject')
[void]$blk.Add($indent + '  $man.source = $src1')
[void]$blk.Add($indent + '}')

# Ensure man.source.length exists; compute from plan
[void]$blk.Add($indent + 'if (-not (Get-Member -InputObject $man.source -Name "length" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '  [int64]$mx = 0')
[void]$blk.Add($indent + '  if ($null -ne $planObj -and (Get-Member -InputObject $planObj -Name "length" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '    try { [int64]$mx = $planObj.length } catch { }')
[void]$blk.Add($indent + '  }')
[void]$blk.Add($indent + '  if ($mx -le 0 -and $null -ne $planObj -and (Get-Member -InputObject $planObj -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '    $bs = @(@($planObj.blocks))')
[void]$blk.Add($indent + '    for($k=0;$k -lt $bs.Count;$k++){')
[void]$blk.Add($indent + '      $b = $bs[$k]')
[void]$blk.Add($indent + '      if ($null -eq $b) { continue }')
[void]$blk.Add($indent + '      $mOff = (Get-Member -InputObject $b -Name "offset" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)')
[void]$blk.Add($indent + '      $mLen = (Get-Member -InputObject $b -Name "length" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)')
[void]$blk.Add($indent + '      if ($mOff -and $mLen) {')
[void]$blk.Add($indent + '        try {')
[void]$blk.Add($indent + '          [int64]$off = $b.offset')
[void]$blk.Add($indent + '          [int64]$ln  = $b.length')
[void]$blk.Add($indent + '          [int64]$end = $off + $ln')
[void]$blk.Add($indent + '          if ($end -gt $mx) { $mx = $end }')
[void]$blk.Add($indent + '        } catch { }')
[void]$blk.Add($indent + '      }')
[void]$blk.Add($indent + '    }')
[void]$blk.Add($indent + '  }')
[void]$blk.Add($indent + '  if ($mx -le 0) { throw "MAN_SOURCE_LENGTH_FALLBACK_FAILED" }')
[void]$blk.Add($indent + '  $man.source | Add-Member -MemberType NoteProperty -Name "length" -Value $mx -Force')
[void]$blk.Add($indent + '  Remove-Variable -Name mx -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '}')

# Replace the original line with our safe one
[void]$blk.Add($indent + '$expectedLen = [int64]$man.source.length')

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
Write-Host ("FINAL_OK: patched " + $Target + " (replaced man.source.length access at line index " + $ix + ")") -ForegroundColor Green
