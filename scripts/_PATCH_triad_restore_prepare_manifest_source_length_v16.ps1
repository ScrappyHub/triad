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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v16_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Locate the v15 block start marker (we replace v15 with v16)
$begin = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*#\s*PATCH_MAN_SOURCE_LEN_V15\s*$'){ $begin=$i; break }
}
if ($begin -lt 0) { Die "NO_V15_BLOCK_START_FOUND" }

# Locate the line that sets expectedLen from man.source.length (within the block)
$end = -1
for($i=$begin+1;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*\$expectedLen\s*=\s*\[int64\]\$man\.source\.length\s*$'){ $end=$i; break }
}
if ($end -lt 0) { Die "NO_EXPECTEDLEN_LINE_FOUND_AFTER_V15_MARKER" }

$indent = ([regex]::Match($lines[$begin], '^(\s*)')).Groups[1].Value

$blk = New-Object System.Collections.Generic.List[string]
[void]$blk.Add($indent + '# PATCH_MAN_SOURCE_LEN_V16')
[void]$blk.Add($indent + '# Ensure $man.source.length exists (bytes). Fallback: plan file on disk (PlanPath or discovery).')
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

# If man.source.length missing, compute from plan file on disk
[void]$blk.Add($indent + 'if (-not (Get-Member -InputObject $man.source -Name "length" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '  # Resolve plan path safely (StrictMode-safe): prefer $PlanPath variable if present; else discover from $OutFile prefix.')
[void]$blk.Add($indent + '  $__planVar = Get-Variable -Name PlanPath -Scope Local -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '  $__planPath = $null')
[void]$blk.Add($indent + '  if ($null -ne $__planVar) { $__planPath = $__planVar.Value }')
[void]$blk.Add($indent + '  if ($null -eq $__planPath -or -not (Test-Path -LiteralPath $__planPath -PathType Leaf)) {')
[void]$blk.Add($indent + '    $outParent = Split-Path -Parent $OutFile')
[void]$blk.Add($indent + '    $outLeaf = Split-Path -Leaf $OutFile')
[void]$blk.Add($indent + '    $pattern = ($outLeaf + ".triad_plan_tree_v1_*.json")')
[void]$blk.Add($indent + '    $cand = Get-ChildItem -LiteralPath $outParent -File -Filter $pattern -ErrorAction Stop | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1')
[void]$blk.Add($indent + '    if ($null -eq $cand) { throw ("MAN_SOURCE_LEN_PLAN_DISCOVERY_FAILED: " + (Join-Path $outParent $pattern)) }')
[void]$blk.Add($indent + '    $__planPath = $cand.FullName')
[void]$blk.Add($indent + '  }')
[void]$blk.Add($indent + '  $planX = Get-Content -Raw -LiteralPath $__planPath -Encoding UTF8 | ConvertFrom-Json')
[void]$blk.Add($indent + '  if ($null -eq $planX) { throw "PLAN_JSON_PARSE_NULL_FOR_LEN" }')
[void]$blk.Add($indent + '  if (-not (Get-Member -InputObject $planX -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) { throw "PLAN_NO_BLOCKS_FOR_LEN" }')
[void]$blk.Add($indent + '  $bs = @(@($planX.blocks))')
[void]$blk.Add($indent + '  [int64]$mx = 0')
[void]$blk.Add($indent + '  for($k=0;$k -lt $bs.Count;$k++){')
[void]$blk.Add($indent + '    $b = $bs[$k]')
[void]$blk.Add($indent + '    if ($null -eq $b) { continue }')
[void]$blk.Add($indent + '    $mOff = (Get-Member -InputObject $b -Name "offset" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)')
[void]$blk.Add($indent + '    $mLen = (Get-Member -InputObject $b -Name "length" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)')
[void]$blk.Add($indent + '    if ($mOff -and $mLen) {')
[void]$blk.Add($indent + '      try {')
[void]$blk.Add($indent + '        [int64]$off = $b.offset')
[void]$blk.Add($indent + '        [int64]$ln  = $b.length')
[void]$blk.Add($indent + '        [int64]$end2 = $off + $ln')
[void]$blk.Add($indent + '        if ($end2 -gt $mx) { $mx = $end2 }')
[void]$blk.Add($indent + '      } catch { }')
[void]$blk.Add($indent + '    }')
[void]$blk.Add($indent + '  }')
[void]$blk.Add($indent + '  if ($mx -le 0) { throw ("MAN_SOURCE_LENGTH_FALLBACK_FAILED_FROM_PLAN: " + $__planPath) }')
[void]$blk.Add($indent + '  $man.source | Add-Member -MemberType NoteProperty -Name "length" -Value $mx -Force')
[void]$blk.Add($indent + '  Remove-Variable -Name mx -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '  Remove-Variable -Name planX -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '  Remove-Variable -Name bs -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '  Remove-Variable -Name __planPath -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '  Remove-Variable -Name __planVar -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '}')

[void]$blk.Add($indent + '$expectedLen = [int64]$man.source.length')

# Replace [begin..end] with v16 block
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
Write-Host ("FINAL_OK: patched " + $Target + " (replaced v15 block lines " + $begin + ".." + $end + " with v16 plan-on-disk fallback)") -ForegroundColor Green
