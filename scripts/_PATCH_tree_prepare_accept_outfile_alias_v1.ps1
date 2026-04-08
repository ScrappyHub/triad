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
$Target = Join-Path $ScriptsDir "triad_restore_tree_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_tree_prepare_outfile_alias_v1_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

# If already present, just parse-gate and exit
if ($txt -match 'Alias\(\s*[\x22']OutFile[\x22']\s*\)') { Parse-GateFile $Target; Write-Host "OK: tree_prepare already has OutFile alias" -ForegroundColor Green; return }

# Find param(...) bounds and the line containing $OutDir within it
$lines = @(@($txt -split "`n",-1))
$start=-1; $end=-1; $idx=-1
for($i=0;$i -lt $lines.Count;$i++){ if ($lines[$i] -match '^\s*param\s*\('){ $start=$i; break } }
if ($start -lt 0) { Die "NO_PARAM_BLOCK" }
for($i=$start+1;$i -lt $lines.Count;$i++){ if ($lines[$i] -match '^\s*\)\s*$'){ $end=$i; break } }
if ($end -lt 0) { Die "PARAM_BLOCK_NOT_CLOSED" }
for($i=$start+1;$i -lt $end;$i++){ if ($lines[$i] -match '\$\bOutDir\b'){ $idx=$i; break } }
if ($idx -lt 0) { Die "NO_OUTDIR_PARAM_LINE_FOUND" }

$indent = ([regex]::Match($lines[$idx], '^(\s*)')).Groups[1].Value
$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $idx) { [void]$out.Add($indent + '[Alias("OutFile")]') }
  [void]$out.Add($lines[$i])
}
$txt2 = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $txt2
Parse-GateFile $Target
Write-Host ("PATCH_OK: added OutFile alias to OutDir param: " + $Target) -ForegroundColor Green
