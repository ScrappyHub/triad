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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v9_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find first occurrence of: $Something.source
$ix = -1
$varName = $null
for($i=0;$i -lt $lines.Count;$i++){
  $m = [regex]::Match($lines[$i], '\$(\w+)\.source\b')
  if ($m.Success) { $ix = $i; $varName = $m.Groups[1].Value; break }
}
if ($ix -lt 0 -or -not $varName) { Die "NO_DOT_SOURCE_ACCESS_FOUND" }

$indent = ([regex]::Match($lines[$ix], '^(\s*)')).Groups[1].Value

# Insert a guard immediately BEFORE the first .source usage
$blk = New-Object System.Collections.Generic.List[string]
[void]$blk.Add($indent + '# --- patched by _PATCH_triad_restore_prepare_source_fallback_v9.ps1 ---')
[void]$blk.Add($indent + ('$__o = $' + $varName))
[void]$blk.Add($indent + 'if ($null -eq $__o) { throw "SOURCE_GUARD_NULL_OBJECT" }')
[void]$blk.Add($indent + 'if (-not (Get-Member -InputObject $__o -Name "source" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '  $pp = (Get-Variable -Name PlanPath -Scope Local -ErrorAction SilentlyContinue)')
[void]$blk.Add($indent + '  $planPathVal = $null')
[void]$blk.Add($indent + '  if ($pp) { $planPathVal = $pp.Value }')
[void]$blk.Add($indent + '  $__o | Add-Member -MemberType NoteProperty -Name "source" -Value ([pscustomobject]@{')
[void]$blk.Add($indent + '    snapshot_dir   = $SnapshotDir')
[void]$blk.Add($indent + '    manifest_path  = $ManifestPath')
[void]$blk.Add($indent + '    out_file       = $OutFile')
[void]$blk.Add($indent + '    plan_path      = $planPathVal')
[void]$blk.Add($indent + '  }) -Force')
[void]$blk.Add($indent + '  Remove-Variable -Name pp -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '  Remove-Variable -Name planPathVal -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '}')
[void]$blk.Add($indent + ('$' + $varName + ' = $__o'))
[void]$blk.Add($indent + 'Remove-Variable -Name __o -ErrorAction SilentlyContinue')
[void]$blk.Add($indent + '# --- end patch ---')

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $ix) {
    foreach($ln in $blk){ [void]$out.Add($ln) }
  }
  [void]$out.Add($lines[$i])
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (inserted source guard before line index " + $ix + "; var=$" + $varName + ")") -ForegroundColor Green
