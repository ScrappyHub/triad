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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v39_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

# Idempotency
if ($txt -match '(?im)PATCH_REWRITE_DOT_LENGTH_V39') {
  Parse-GateFile $Target
  Write-Host ("OK: v39 already present: " + $Target) -ForegroundColor Green
  return
}

# Ensure helper exists (in case v38 didn't insert for some reason)
if ($txt -notmatch '(?im)^\s*function\s+Get-JsonPropValue\s*\(') {
  $m = [regex]::Match($txt, '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
  if (-not $m.Success) { Die "NO_SET_STRICTMODE_ANCHOR_FOUND_FOR_HELPER_V39" }
  $pos = $m.Index + $m.Length
  $helper = @(
    '',
    '# PATCH_REWRITE_DOT_LENGTH_V39',
    'function Get-JsonPropValue([Parameter(Mandatory=$true)]$Obj,[Parameter(Mandatory=$true)][string]$Name){',
    '  try {',
    '    if ($null -eq $Obj) { return $null }',
    '    $p = $Obj.PSObject.Properties[$Name]',
    '    if ($null -eq $p) { return $null }',
    '    return $p.Value',
    '  } catch { return $null }',
    '}',
    ''
  ) -join "`n"
  $txt = $txt.Substring(0,$pos) + "`n" + $helper + $txt.Substring($pos)
} else {
  # still mark so idempotency works even if helper already existed
  $txt = "# PATCH_REWRITE_DOT_LENGTH_V39`n" + $txt
}

$before = $txt

# Rewrite ALL occurrences of: $var.length / $var.Length (StrictMode safe)
# NOTE: intentionally only targets direct $<name>.length patterns (not arbitrary expressions)
$txt = [regex]::Replace(
  $txt,
  '(?im)(\$(?:script:|global:|local:)?[A-Za-z_][A-Za-z0-9_]*)\.(length)\b',
  'Get-JsonPropValue $1 "length"'
)
$txt = [regex]::Replace(
  $txt,
  '(?im)(\$(?:script:|global:|local:)?[A-Za-z_][A-Za-z0-9_]*)\.(Length)\b',
  'Get-JsonPropValue $1 "Length"'
)

if ($txt -eq $before) { Die "PATCH_NO_CHANGE_V39: no `$.length/`$.Length patterns found to rewrite (verify script drift?)" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v39 rewrote `$.length/`$.Length -> Get-JsonPropValue)") -ForegroundColor Green
