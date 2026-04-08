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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v37_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find the schema unexpected guard line
$hit = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)MANIFEST_SCHEMA_UNEXPECTED'){
    $hit = $i; break
  }
}
if ($hit -lt 0) { Die "NO_MANIFEST_SCHEMA_UNEXPECTED_GUARD_FOUND" }

# Idempotency
for($j=[Math]::Max(0,$hit-10); $j -le [Math]::Min($hit+10,$lines.Count-1); $j++){
  if ($lines[$j] -match '(?im)PATCH_ACCEPT_SNAPSHOT_TREE_V37'){
    Parse-GateFile $Target
    Write-Host ("OK: v37 already present: " + $Target) -ForegroundColor Green
    return
  }
}

# Build replacement allowlist block
$indent = ([regex]::Match($lines[$hit], '^(\s*)')).Groups[1].Value

$rep = New-Object System.Collections.Generic.List[string]
[void]$rep.Add($indent + '# PATCH_ACCEPT_SNAPSHOT_TREE_V37')
[void]$rep.Add($indent + '# Accept both snapshot schemas: legacy + tree.')
[void]$rep.Add($indent + '$__schema = ""')
[void]$rep.Add($indent + 'try {')
[void]$rep.Add($indent + '  $pS = $man.PSObject.Properties["schema"]')
[void]$rep.Add($indent + '  if ($null -ne $pS -and $null -ne $pS.Value) { $__schema = [string]$pS.Value }')
[void]$rep.Add($indent + '} catch { $__schema = "" }')
[void]$rep.Add($indent + '$__ok = $false')
[void]$rep.Add($indent + 'if ($__schema -eq "triad.snapshot_tree.v1") { $__ok = $true }')
[void]$rep.Add($indent + 'if ($__schema -eq "triad.snapshot.v1") { $__ok = $true }')
[void]$rep.Add($indent + 'if ($__schema -eq "triad.snapshot_v1") { $__ok = $true }')
[void]$rep.Add($indent + 'if ($__schema -eq "triad.snapshot.blocks.v1") { $__ok = $true }')
[void]$rep.Add($indent + 'if (-not $__ok) { Die ("MANIFEST_SCHEMA_UNEXPECTED: " + $__schema) }')
[void]$rep.Add($indent + 'Remove-Variable -Name pS -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + 'Remove-Variable -Name __schema -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + 'Remove-Variable -Name __ok -ErrorAction SilentlyContinue')

# Case A: single-line if guard (contains "if (" on same line)
$lineIsSingleIf = ($lines[$hit] -match '(?im)^\s*if\s*\(')

if ($lineIsSingleIf) {
  $out = New-Object System.Collections.Generic.List[string]
  for($i=0;$i -lt $lines.Count;$i++){
    if ($i -eq $hit) {
      foreach($ln in $rep){ [void]$out.Add($ln) }
      continue
    }
    [void]$out.Add($lines[$i])
  }
  $final = ($out.ToArray() -join "`n")
  Write-Utf8NoBomLf $Target $final
  Parse-GateFile $Target
  Write-Host ("FINAL_OK: patched " + $Target + " (v37 replaced single-line schema guard at line " + $hit + ")") -ForegroundColor Green
  return
}

# Case B: multi-line guard (replace from nearest preceding if(...) to first subsequent line containing "}")
$ifStart = -1
for($i=$hit; $i -ge [Math]::Max(0,$hit-20); $i--){
  if ($lines[$i] -match '(?im)^\s*if\s*\('){ $ifStart = $i; break }
}
if ($ifStart -lt 0) { Die "NO_SCHEMA_IF_START_FOUND_V37" }

$ifEnd = -1
for($i=$hit; $i -lt [Math]::Min($hit+40,$lines.Count); $i++){
  if ($lines[$i] -match '\}'){ $ifEnd = $i; break }
}
if ($ifEnd -lt 0) { Die "NO_SCHEMA_IF_END_FOUND_V37" }

$out2 = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $ifStart) {
    foreach($ln in $rep){ [void]$out2.Add($ln) }
    $i = $ifEnd
    continue
  }
  [void]$out2.Add($lines[$i])
}

$final2 = ($out2.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final2
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v37 replaced schema guard block lines " + $ifStart + ".." + $ifEnd + ")") -ForegroundColor Green
