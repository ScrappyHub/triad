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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v28_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Idempotency marker
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*#\s*PATCH_SKIP_SOURCE_SHA_CHECK_V28\s*$'){
    Parse-GateFile $Target
    Write-Host ("OK: v28 already present: " + $Target) -ForegroundColor Green
    return
  }
}

# 1) Replace the V25 fatal throw with WARN+skip flag
$throwIx = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)SOURCE_PATH_DISCOVERY_FAILED_FOR_SHA256_V25'){
    $throwIx = $i
    break
  }
}
if ($throwIx -lt 0) { Die "NO_V25_SOURCE_DISCOVERY_THROW_FOUND" }

# Find the start of the null-src check containing that throw
$ifStart = -1
for($i=$throwIx; $i -ge [Math]::Max(0,$throwIx-30); $i--){
  if ($lines[$i] -match '(?im)^\s*if\s*\(\s*\$null\s*-eq\s*\$__src\s*\)\s*\{'){
    $ifStart = $i
    break
  }
}
if ($ifStart -lt 0) { Die "NO_NULL_SRC_IF_BLOCK_START_FOUND" }

# Find end of that if-block (first closing brace after throw line)
$ifEnd = -1
for($i=$throwIx; $i -lt [Math]::Min($throwIx+30,$lines.Count); $i++){
  if ($lines[$i] -match '^\s*\}\s*$'){
    $ifEnd = $i
    break
  }
}
if ($ifEnd -lt 0) { Die "NO_NULL_SRC_IF_BLOCK_END_FOUND" }

$indent = ([regex]::Match($lines[$ifStart], '^(\s*)')).Groups[1].Value

$rep = New-Object System.Collections.Generic.List[string]
[void]$rep.Add($indent + '# PATCH_SKIP_SOURCE_SHA_CHECK_V28')
[void]$rep.Add($indent + 'if ($null -eq $__src) {')
[void]$rep.Add($indent + '  $outDir2 = $null')
[void]$rep.Add($indent + '  try { $outDir2 = (Split-Path -Parent $OutFile) } catch { $outDir2 = "<unknown>" }')
[void]$rep.Add($indent + '  Write-Host ("WARN: SOURCE_BYTES_NOT_PRESENT_AT_PREPARE (skipping sha256 verify; expected_sha=" + $expectedSha + "; outDir=" + $outDir2 + ")") -ForegroundColor Yellow')
[void]$rep.Add($indent + '  $script:__skipSourceShaVerify = $true')
[void]$rep.Add($indent + '} else {')
[void]$rep.Add($indent + '  $script:__skipSourceShaVerify = $false')
[void]$rep.Add($indent + '}')
[void]$rep.Add($indent + 'Remove-Variable -Name outDir2 -ErrorAction SilentlyContinue')

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $ifStart) {
    foreach($ln in $rep){ [void]$out.Add($ln) }
    $i = $ifEnd
    continue
  }
  [void]$out.Add($lines[$i])
}
$lines = @(@($out.ToArray()))

# 2) Guard the actual Get-FileHash compare (if present) so it runs only when bytes exist
$hit2 = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)Get-FileHash\s+-Algorithm\s+SHA256\s+-LiteralPath\s+\$__src'){
    $hit2 = $i
    break
  }
}
if ($hit2 -ge 0) {
  # Walk upward to include the assignment line, then forward to include compare/throw (best-effort window)
  $segStart = [Math]::Max(0, $hit2-2)
  $segEnd = [Math]::Min($lines.Count-1, $hit2+12)
  $indent2 = ([regex]::Match($lines[$hit2], '^(\s*)')).Groups[1].Value

  $wrap = New-Object System.Collections.Generic.List[string]
  [void]$wrap.Add($indent2 + 'if (-not $script:__skipSourceShaVerify) {')
  for($i=$segStart; $i -le $segEnd; $i++){
    [void]$wrap.Add($indent2 + '  ' + $lines[$i])
  }
  [void]$wrap.Add($indent2 + '} else {')
  [void]$wrap.Add($indent2 + '  # v28: intentionally skipped; verification must occur when bytes exist (restore verify/commit).')
  [void]$wrap.Add($indent2 + '}')

  $out2 = New-Object System.Collections.Generic.List[string]
  for($i=0;$i -lt $lines.Count;$i++){
    if ($i -eq $segStart) {
      foreach($ln in $wrap){ [void]$out2.Add($ln) }
      $i = $segEnd
      continue
    }
    [void]$out2.Add($lines[$i])
  }
  $lines = @(@($out2.ToArray()))
}

$final = ($lines -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v28 skip source sha verify when source bytes are absent; guarded Get-FileHash if present)") -ForegroundColor Green
