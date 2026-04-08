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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v46_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

# Idempotency
if ($txt -match '(?im)PATCH_BLOCKS_INDEX_SAFE_V46') {
  Parse-GateFile $Target
  Write-Host ("OK: v46 already present: " + $Target) -ForegroundColor Green
  return
}

$before = $txt

# Insert AtOrNull helper after first Set-StrictMode -Version Latest
$m = [regex]::Match($txt, '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
if (-not $m.Success) { Die "NO_SET_STRICTMODE_ANCHOR_FOUND_V46" }
$pos = $m.Index + $m.Length

$helper = @(
  '',
  '# PATCH_BLOCKS_INDEX_SAFE_V46',
  'function AtOrNull([Parameter(Mandatory=$true)]$Arr,[Parameter(Mandatory=$true)][int]$Index){',
  '  if($null -eq $Arr){ return $null }',
  '  $a = @(@($Arr))',
  '  if($Index -lt 0){ return $null }',
  '  if($Index -ge $a.Count){ return $null }',
  '  return $a[$Index]',
  '}',
  ''
) -join "`n"

$txt = $txt.Substring(0,$pos) + "`n" + $helper + $txt.Substring($pos)

# Rewrite ONLY the risky blocks indexer patterns produced by our earlier rewrite:
#   (ArrOf <expr> "blocks")[0]  -> (AtOrNull (ArrOf <expr> "blocks") 0)
#   (ArrOf <expr> "blocks")[1]  -> (AtOrNull (ArrOf <expr> "blocks") 1)
$txt = [regex]::Replace(
  $txt,
  '(?ims)\(\s*ArrOf\s+([^\)]*?)\s+"blocks"\s*\)\s*\[\s*(\d+)\s*\]',
  '(AtOrNull (ArrOf $1 "blocks") $2)'
)

if ($txt -eq $before) { Die "PATCH_NO_CHANGE_V46: no (ArrOf ... ""blocks"")[n] patterns found (script drift?)" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v46 makes blocks indexing safe via AtOrNull)") -ForegroundColor Green
