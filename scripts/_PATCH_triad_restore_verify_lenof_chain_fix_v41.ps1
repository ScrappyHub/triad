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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v41_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

# Idempotency
if ($txt -match '(?im)PATCH_LENOF_CHAIN_V41') {
  Parse-GateFile $Target
  Write-Host ("OK: v41 already present: " + $Target) -ForegroundColor Green
  return
}

# Ensure LenOf exists (v40 should have installed it, but be defensive)
if ($txt -notmatch '(?im)^\s*function\s+LenOf\s*\(') {
  $m = [regex]::Match($txt, '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
  if (-not $m.Success) { Die "NO_SET_STRICTMODE_ANCHOR_FOUND_FOR_LENOF_V41" }
  $pos = $m.Index + $m.Length

  $helper = @(
    '',
    '# PATCH_LENOF_CHAIN_V41',
    'function LenOf([Parameter(Mandatory=$true)]$Obj){',
    '  try {',
    '    if ($null -eq $Obj) { return $null }',
    '    try { $pLen = $Obj.PSObject.Properties["Length"]; if ($null -ne $pLen) { return $pLen.Value } } catch { }',
    '    try { $pLen2 = $Obj.PSObject.Properties["length"]; if ($null -ne $pLen2) { return $pLen2.Value } } catch { }',
    '    return $null',
    '  } catch { return $null }',
    '}',
    ''
  ) -join "`n"

  $txt = $txt.Substring(0,$pos) + "`n" + $helper + $txt.Substring($pos)
} else {
  $txt = "# PATCH_LENOF_CHAIN_V41`n" + $txt
}

$before = $txt

# Rewrite *chained* member access ending with .length/.Length:
#   $x.y.length   -> (LenOf $x.y)
#   $planX.roots.Length -> (LenOf $planX.roots)
$txt = [regex]::Replace(
  $txt,
  '(?im)(\$(?:script:|global:|local:)?[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+)\.(length|Length)\b',
  '(LenOf $1)'
)

if ($txt -eq $before) { Die "PATCH_NO_CHANGE_V41: no chained `$.a.b.length patterns found (script drift?)" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v41 rewrote chained `$.a.b.length/Length -> (LenOf `$.a.b))") -ForegroundColor Green
