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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v43b_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

# Idempotency for THIS patcher
if ($txt -match '(?im)PATCH_BLOCKS_CHAIN_V43B') {
  Parse-GateFile $Target
  Write-Host ("OK: v43b already present: " + $Target) -ForegroundColor Green
  return
}

# Insert helpers after the FIRST Set-StrictMode -Version Latest line.
$m = [regex]::Match($txt, '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
if (-not $m.Success) { Die "NO_SET_STRICTMODE_ANCHOR_FOUND_V43B" }
$pos = $m.Index + $m.Length

$helpers = @(
  '',
  '# PATCH_BLOCKS_CHAIN_V43B',
  'function PropOf([Parameter(Mandatory=$true)]$Obj,[Parameter(Mandatory=$true)][string]$Name){',
  ' try {',
  '   if ($null -eq $Obj) { return $null }',
  '   $p = $Obj.PSObject.Properties[$Name]',
  '   if ($null -eq $p) { return $null }',
  '   return $p.Value',
  ' } catch { return $null }',
  '}',
  'function ArrOf([Parameter(Mandatory=$true)]$Obj,[Parameter(Mandatory=$true)][string]$Name){',
  ' $v = PropOf $Obj $Name',
  ' if ($null -eq $v) { return @() }',
  ' return @(@($v))',
  '}',
  ''
) -join "`n"

$txt = $txt.Substring(0,$pos) + "`n" + $helpers + $txt.Substring($pos)

$before = $txt

# Rewrite member-chains ending with .blocks/.Blocks (including nested: $x.y.blocks)
$txt = [regex]::Replace(
  $txt,
  '(?im)(\$(?:script:|global:|local:)?[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\.(blocks|Blocks)\b',
  '(ArrOf $1 "blocks")'
)

if ($txt -eq $before) { Die "PATCH_NO_CHANGE_V43B: no `$.blocks patterns found to rewrite (script drift?)" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v43b inserted helpers after StrictMode + rewrote `$.blocks chains -> (ArrOf ... ""blocks""))") -ForegroundColor Green
