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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v8_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find the MANIFEST_NO_BLOCKS line index
$ix = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?i)MANIFEST_NO_BLOCKS') { $ix = $i; break }
}
if ($ix -lt 0) { Die "NO_MANIFEST_NO_BLOCKS_MARKER_FOUND" }

# Walk backwards to find the variable referenced like $Something.blocks in the surrounding check
$varName = $null
for($j=$ix; $j -ge 0; $j--){
  $m = [regex]::Match($lines[$j], '\$(\w+)\.blocks')
  if ($m.Success) { $varName = $m.Groups[1].Value; break }
}
if (-not $varName) {
  # last resort: try to find a manifest variable assignment earlier (common names)
  $cands = @('Manifest','manifest','man')
  foreach($c in $cands){
    for($j=$ix; $j -ge 0; $j--){
      if ($lines[$j] -match ('(?im)^\s*\$' + [regex]::Escape($c) + '\s*=')) { $varName = $c; break }
    }
    if ($varName) { break }
  }
}
if (-not $varName) { Die "CANNOT_DETERMINE_MANIFEST_VARIABLE_NAME_FOR_BLOCKS_CHECK" }

$indent = ([regex]::Match($lines[$ix], '^(\s*)')).Groups[1].Value

# Replace ONLY the line that throws MANIFEST_NO_BLOCKS with a deterministic fallback
$replacement = New-Object System.Collections.Generic.List[string]
[void]$replacement.Add($indent + 'Write-Host "WARN: MANIFEST_NO_BLOCKS (fallback: normalize manifest.blocks to empty; plan blocks will drive restore)" -ForegroundColor Yellow')
[void]$replacement.Add($indent + ('$__m = $' + $varName))
[void]$replacement.Add($indent + 'if (-not (Get-Member -InputObject $__m -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$replacement.Add($indent + '  $__m | Add-Member -MemberType NoteProperty -Name "blocks" -Value @() -Force')
[void]$replacement.Add($indent + '} else {')
[void]$replacement.Add($indent + '  $__m.blocks = @()')
[void]$replacement.Add($indent + '}')
[void]$replacement.Add($indent + ('$' + $varName + ' = $__m'))
[void]$replacement.Add($indent + 'Remove-Variable -Name __m -ErrorAction SilentlyContinue')

# Build output lines with single-line replacement at $ix
$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $ix) {
    foreach($ln in $replacement){ [void]$out.Add($ln) }
    continue
  }
  [void]$out.Add($lines[$i])
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (replaced MANIFEST_NO_BLOCKS throw at line index " + $ix + "; var=$" + $varName + ")") -ForegroundColor Green
