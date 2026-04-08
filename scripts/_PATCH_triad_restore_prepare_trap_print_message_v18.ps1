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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v18_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find the TRIAD_TRAP_V13 catch block area and ensure we can patch it safely.
# We patch by inserting message prints right after the existing LINE print.
$ix = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*Write-Host\s+\(\s*"TRIAD_TRAP_V13:\s*LINE:' ){ $ix = $i; break }
}
if ($ix -lt 0) { Die "NO_TRAP_V13_LINE_PRINT_FOUND" }

# Idempotent: if already printing MESSAGE, do nothing
for($j=$ix; $j -lt [Math]::Min($ix+40,$lines.Count); $j++){
  if ($lines[$j] -match '(?im)TRIAD_TRAP_V13:\s*MESSAGE:' ){ 
    Parse-GateFile $Target
    Write-Host ("OK: v18 trap message prints already present: " + $Target) -ForegroundColor Green
    return
  }
}

$indent = ([regex]::Match($lines[$ix], '^(\s*)')).Groups[1].Value

$ins = New-Object System.Collections.Generic.List[string]
[void]$ins.Add($indent + 'try {')
[void]$ins.Add($indent + '  $msg = $null')
[void]$ins.Add($indent + '  try { $msg = $_.Exception.Message } catch { $msg = $null }')
[void]$ins.Add($indent + '  if ($null -ne $msg -and ($msg.ToString().Length -gt 0)) {')
[void]$ins.Add($indent + '    Write-Host ("TRIAD_TRAP_V13: MESSAGE: " + $msg) -ForegroundColor Yellow')
[void]$ins.Add($indent + '  } else {')
[void]$ins.Add($indent + '    Write-Host "TRIAD_TRAP_V13: MESSAGE: <null>" -ForegroundColor Yellow')
[void]$ins.Add($indent + '  }')
[void]$ins.Add($indent + '  $inner = $null')
[void]$ins.Add($indent + '  try { $inner = $_.Exception.InnerException } catch { $inner = $null }')
[void]$ins.Add($indent + '  if ($null -ne $inner) {')
[void]$ins.Add($indent + '    try { Write-Host ("TRIAD_TRAP_V13: INNER: " + $inner.Message) -ForegroundColor DarkYellow } catch { }')
[void]$ins.Add($indent + '  }')
[void]$ins.Add($indent + '} catch { }')

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  [void]$out.Add($lines[$i])
  if ($i -eq $ix) {
    foreach($ln in $ins){ [void]$out.Add($ln) }
  }
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (added TRIAD_TRAP_V13 message prints after LINE print at index " + $ix + ")") -ForegroundColor Green
