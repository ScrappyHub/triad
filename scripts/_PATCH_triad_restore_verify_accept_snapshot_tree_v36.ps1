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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v36_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find the hard-throw line: MANIFEST_SCHEMA_UNEXPECTED: ...
$hit = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)MANIFEST_SCHEMA_UNEXPECTED'){
    $hit = $i
    break
  }
}
if ($hit -lt 0) { Die "NO_MANIFEST_SCHEMA_UNEXPECTED_GUARD_FOUND" }

# Idempotency
for($j=[Math]::Max(0,$hit-8); $j -le [Math]::Min($hit+12,$lines.Count-1); $j++){
  if ($lines[$j] -match '(?im)PATCH_ACCEPT_SNAPSHOT_TREE_V36'){
    Parse-GateFile $Target
    Write-Host ("OK: v36 already present: " + $Target) -ForegroundColor Green
    return
  }
}

# Replace the entire guard "if (...) { Die MANIFEST_SCHEMA_UNEXPECTED... }" with an allowlist.
# We locate the nearest preceding "if (" line and following "}" line around $hit.
$ifStart = -1
for($i=$hit; $i -ge [Math]::Max(0,$hit-10); $i--){
  if ($lines[$i] -match '(?im)^\s*if\s*\('){ $ifStart = $i; break }
}
if ($ifStart -lt 0) { Die "NO_SCHEMA_IF_START_FOUND" }

$ifEnd = -1
for($i=$hit; $i -lt [Math]::Min($hit+12,$lines.Count); $i++){
  if ($lines[$i] -match '^\s*\}\s*$'){ $ifEnd = $i; break }
}
if ($ifEnd -lt 0) { Die "NO_SCHEMA_IF_END_FOUND" }

$indent = ([regex]::Match($lines[$ifStart], '^(\s*)')).Groups[1].Value

$rep = New-Object System.Collections.Generic.List[string]
[void]$rep.Add($indent + '# PATCH_ACCEPT_SNAPSHOT_TREE_V36')
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

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $ifStart) {
    foreach($ln in $rep){ [void]$out.Add($ln) }
    $i = $ifEnd
    continue
  }
  [void]$out.Add($lines[$i])
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v36 allowlisted triad.snapshot_tree.v1; replaced lines " + $ifStart + ".." + $ifEnd + ")") -ForegroundColor Green
