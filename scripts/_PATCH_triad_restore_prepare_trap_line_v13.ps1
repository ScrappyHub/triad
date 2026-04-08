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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v13_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
if ($txt -match '(?im)^\s*#\s*TRIAD_TRAP_V13\s*$') {
  Parse-GateFile $Target
  Write-Host ("OK: trap v13 already present: " + $Target) -ForegroundColor Green
  return
}

$lines = @(@($txt -split "`n",-1))

# Insert trap after Set-StrictMode line if present; else near top after $ErrorActionPreference assignment.
$insAt = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$') { $insAt = $i + 1; break }
}
if ($insAt -lt 0) {
  for($i=0;$i -lt $lines.Count;$i++){
    if ($lines[$i] -match '(?im)^\s*\$ErrorActionPreference\s*=\s*"?Stop"?\s*$') { $insAt = $i + 1; break }
  }
}
if ($insAt -lt 0) { $insAt = 0 }

$trap = New-Object System.Collections.Generic.List[string]
[void]$trap.Add('# TRIAD_TRAP_V13')
[void]$trap.Add('trap {')
[void]$trap.Add('  try {')
[void]$trap.Add('    $inv = $_.InvocationInfo')
[void]$trap.Add('    $ln  = $inv.ScriptLineNumber')
[void]$trap.Add('    $txt = $inv.Line')
[void]$trap.Add('    Write-Host ("TRIAD_TRAP_V13: ERR at line " + $ln) -ForegroundColor Red')
[void]$trap.Add('    if ($txt) { Write-Host ("TRIAD_TRAP_V13: LINE: " + $txt) -ForegroundColor Red }')
[void]$trap.Add('  } catch { }')
[void]$trap.Add('  throw')
[void]$trap.Add('}')
[void]$trap.Add('')

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $insAt) {
    foreach($ln in $trap){ [void]$out.Add($ln) }
  }
  [void]$out.Add($lines[$i])
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (installed trap v13 at index " + $insAt + ")") -ForegroundColor Green
