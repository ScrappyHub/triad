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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v29_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find the v28 block marker
$mark = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*#\s*PATCH_SKIP_SOURCE_SHA_CHECK_V28\s*$'){ $mark = $i; break }
}
if ($mark -lt 0) { Die "NO_V28_MARKER_FOUND" }

# Find the specific WARN line that references $expectedSha (StrictMode unsafe)
$warnIx = -1
for($i=$mark; $i -lt [Math]::Min($mark+80,$lines.Count); $i++){
  if ($lines[$i] -match '(?im)WARN:\s*SOURCE_BYTES_NOT_PRESENT_AT_PREPARE' -and $lines[$i] -match '(?im)\$expectedSha'){
    $warnIx = $i
    break
  }
}
if ($warnIx -lt 0) { Die "NO_V28_WARN_LINE_WITH_EXPECTEDSHA_FOUND" }

$indent = ([regex]::Match($lines[$warnIx], '^(\s*)')).Groups[1].Value

# Replace that single Write-Host line with a StrictMode-safe block
$rep = New-Object System.Collections.Generic.List[string]
[void]$rep.Add($indent + '# PATCH_SKIP_SOURCE_SHA_CHECK_V29 (StrictMode-safe expected sha)')
[void]$rep.Add($indent + '$__es = ""')
[void]$rep.Add($indent + '$__vEs = Get-Variable -Name expectedSha -Scope Local -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + 'if ($null -ne $__vEs -and $null -ne $__vEs.Value) {')
[void]$rep.Add($indent + '  try { $__es = [string]$__vEs.Value } catch { $__es = "" }')
[void]$rep.Add($indent + '}')
[void]$rep.Add($indent + 'Write-Host ("WARN: SOURCE_BYTES_NOT_PRESENT_AT_PREPARE (skipping sha256 verify; expected_sha=" + $__es + "; outDir=" + $outDir2 + ")") -ForegroundColor Yellow')
[void]$rep.Add($indent + 'Remove-Variable -Name __vEs -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + 'Remove-Variable -Name __es -ErrorAction SilentlyContinue')

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $warnIx) {
    foreach($ln in $rep){ [void]$out.Add($ln) }
    continue
  }
  [void]$out.Add($lines[$i])
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v29 StrictMode-safe expectedSha in v28 warn; line=" + $warnIx + ")") -ForegroundColor Green
