param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  if ([string]::IsNullOrWhiteSpace($Path)) { Die "WRITE_UTF8_PATH_EMPTY" }
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateFile([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }; $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8; $null = [ScriptBlock]::Create($raw) }

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("MISSING_REPO: " + $RepoRoot) }
$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_dispatch_tree_v1_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$raw = Get-Content -Raw -LiteralPath $Target -Encoding UTF8
$txt = $raw.Replace("`r`n","`n").Replace("`r","`n")

# Replace the existing schema guard that throws MANIFEST_SCHEMA_UNEXPECTED with a dispatcher block
$pat = '(?s)if\s*\([^\)]*\)\s*\{[^\}]*MANIFEST_SCHEMA_UNEXPECTED[^\}]*\}'
$m = [regex]::Match($txt,$pat)
if (-not $m.Success) { Die "DISPATCH_TREE_V1_ANCHOR_NOT_FOUND: expected schema guard containing MANIFEST_SCHEMA_UNEXPECTED" }

$block = New-Object System.Collections.Generic.List[string]
[void]$block.Add('# Schema dispatch (compat v1): allow snapshot_tree by delegating to tree prepare')
[void]$block.Add('$schemaVal = $null')
[void]$block.Add('$v = Get-Variable -Name schema -Scope 0 -ErrorAction SilentlyContinue')
[void]$block.Add('if ($v) { $schemaVal = [string]$v.Value } else {')
[void]$block.Add('  $vm = Get-Variable -Name m -Scope 0 -ErrorAction SilentlyContinue')
[void]$block.Add('  if ($vm) { try { $schemaVal = [string]$vm.Value.schema } catch { $schemaVal = $null } } else {')
[void]$block.Add('    $vman = Get-Variable -Name manifest -Scope 0 -ErrorAction SilentlyContinue')
[void]$block.Add('    if ($vman) { try { $schemaVal = [string]$vman.Value.schema } catch { $schemaVal = $null } }' )
[void]$block.Add('  }' )
[void]$block.Add('}')
[void]$block.Add('if ($schemaVal -eq "triad.snapshot_tree.v1") {')
[void]$block.Add('  $tree = Join-Path $PSScriptRoot "triad_restore_tree_prepare_v1.ps1"' )
[void]$block.Add('  if (-not (Test-Path -LiteralPath $tree -PathType Leaf)) { Die ("MISSING_TREE_PREP: " + $tree) }' )
[void]$block.Add('  & $tree @PSBoundParameters' )
[void]$block.Add('  return' )
[void]$block.Add('}' )
[void]$block.Add('if ($schemaVal -ne "triad.snapshot.v1") { Die ("MANIFEST_SCHEMA_UNEXPECTED: " + $schemaVal) }' )

$rep = ($block.ToArray() -join "`n")
$txt2 = [regex]::Replace($txt,$pat,[regex]::Escape($rep))
# Undo regex escaping we just applied: we want literal block text inserted, not escaped chars
$txt2 = $txt2.Replace([regex]::Escape($rep), $rep)

Write-Utf8NoBomLf $Target $txt2
Parse-GateFile $Target
Write-Host ("PATCH_OK: restore_prepare now dispatches snapshot_tree -> tree_prepare: " + $Target) -ForegroundColor Green
Write-Host ("backupdir: " + $BackupDir) -ForegroundColor DarkGray
