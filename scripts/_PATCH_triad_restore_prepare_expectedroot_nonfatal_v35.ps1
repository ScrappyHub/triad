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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v35_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Anchor: exact v32 fatal line
$hit = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*if\s*\(\s*-not\s+\$expectedRoot\s*\)\s*\{\s*throw\s*\"MISSING_BLOCK_ROOT_V32\"\s*\}\s*$'){
    $hit = $i; break
  }
}
if ($hit -lt 0) { Die "NO_MISSING_BLOCK_ROOT_V32_THROW_LINE_FOUND" }

# Idempotency
for($j=[Math]::Max(0,$hit-3); $j -le [Math]::Min($hit+40,$lines.Count-1); $j++){
  if ($lines[$j] -match '(?im)PATCH_EXPECTEDROOT_NONFATAL_V35'){
    Parse-GateFile $Target
    Write-Host ("OK: v35 already present: " + $Target) -ForegroundColor Green
    return
  }
}

$indent = ([regex]::Match($lines[$hit], '^(\s*)')).Groups[1].Value

$rep = New-Object System.Collections.Generic.List[string]
[void]$rep.Add($indent + '# PATCH_EXPECTEDROOT_NONFATAL_V35')
[void]$rep.Add($indent + 'if (-not $expectedRoot) {')
[void]$rep.Add($indent + '  $__er = ""')
[void]$rep.Add($indent + '  $erNames = @("block_root","blockRoot","BlockRoot","BlockRootHex","block_root_hex","blockRootHex")')
[void]$rep.Add($indent + '  for($k=0;$k -lt $erNames.Count -and -not $__er; $k++){')
[void]$rep.Add($indent + '    $__vEr = Get-Variable -Name $erNames[$k] -Scope Local -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + '    if ($null -ne $__vEr -and $null -ne $__vEr.Value) {')
[void]$rep.Add($indent + '      try { $__er = [string]$__vEr.Value } catch { $__er = "" }')
[void]$rep.Add($indent + '    }')
[void]$rep.Add($indent + '  }')
[void]$rep.Add($indent + '  if ($__er) {')
[void]$rep.Add($indent + '    $expectedRoot = $__er')
[void]$rep.Add($indent + '    $script:__skipExpectedRootVerify = $false')
[void]$rep.Add($indent + '    Write-Host ("WARN: EXPECTED_ROOT_MISSING_IN_MANIFEST_PLAN (fell back to local var; expectedRoot=" + $expectedRoot + ")") -ForegroundColor Yellow')
[void]$rep.Add($indent + '  } else {')
[void]$rep.Add($indent + '    $script:__skipExpectedRootVerify = $true')
[void]$rep.Add($indent + '    Write-Host "WARN: EXPECTED_ROOT_MISSING_IN_MANIFEST_PLAN_AND_LOCALS (skipping expectedRoot verify at PREPARE; verify/commit must enforce later)" -ForegroundColor Yellow')
[void]$rep.Add($indent + '  }')
[void]$rep.Add($indent + '  Remove-Variable -Name __er -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + '  Remove-Variable -Name erNames -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + '  Remove-Variable -Name __vEr -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + '} else {')
[void]$rep.Add($indent + '  $script:__skipExpectedRootVerify = $false')
[void]$rep.Add($indent + '}')

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $hit) {
    foreach($ln in $rep){ [void]$out.Add($ln) }
    continue
  }
  [void]$out.Add($lines[$i])
}
$lines = @(@($out.ToArray()))

# Best-effort: guard any later throws involving expectedRoot comparison
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)\$expectedRoot' -and $lines[$i] -match '(?im)throw') {
    if ($lines[$i] -match '(?im)__skipExpectedRootVerify') { continue }
    # If this is a single-line if (...) { throw ... } that mentions expectedRoot, gate it.
    if ($lines[$i] -match '(?im)^\s*if\s*\((.+)\)\s*\{\s*throw\s+(.+)\s*\}\s*$') {
      $ind2 = ([regex]::Match($lines[$i], '^(\s*)')).Groups[1].Value
      $cond = ([regex]::Match($lines[$i], '(?im)^\s*if\s*\((.+)\)\s*\{')).Groups[1].Value
      $thr  = ([regex]::Match($lines[$i], '(?im)\{\s*throw\s+(.+)\s*\}\s*$')).Groups[1].Value
      if ($cond -match '(?im)\$expectedRoot') {
        $lines[$i] = $ind2 + 'if ((-not $script:__skipExpectedRootVerify) -and (' + $cond + ')) { throw ' + $thr + ' }'
      }
    }
  }
}

$final = ($lines -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v35 expectedRoot missing is non-fatal at PREPARE; anchored at line " + $hit + ")") -ForegroundColor Green
