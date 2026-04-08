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
function Parse-GateFile([string]$Path){ $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8; $null = [ScriptBlock]::Create($raw) }

$ScriptsDir = Join-Path $RepoRoot "scripts"
$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_restore_prepare_dispatch_args_v1_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find first line that mentions triad_restore_tree_prepare_v1.ps1 and replace it
$hit = -1
for($i=0;$i -lt $lines.Count;$i++){ if ($lines[$i] -match 'triad_restore_tree_prepare_v1\.ps1'){ $hit=$i; break } }
if ($hit -lt 0) { Die "NO_TREE_PREP_INVOKE_LINE_FOUND" }

# Replace the entire invoke line with an argument-complete, non-interactive call.
# NOTE: OutFile is what restore_prepare receives; tree_prepare now aliases OutFile->OutDir.
$indent = ([regex]::Match($lines[$hit], '^(\s*)')).Groups[1].Value
$lines[$hit] = $indent + 'return (& $TreePrep -RepoRoot $RepoRoot -SnapshotDir $SnapshotDir -OutFile $OutFile -ManifestPath $ManifestPath)'

$txt2 = ($lines -join "`n")
Write-Utf8NoBomLf $Target $txt2
Parse-GateFile $Target
Write-Host ("PATCH_OK: restore_prepare tree dispatch now passes args: " + $Target) -ForegroundColor Green
