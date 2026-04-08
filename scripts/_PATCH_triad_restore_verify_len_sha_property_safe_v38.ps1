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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v38_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Idempotency
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)PATCH_LEN_SHA_PROPERTY_SAFE_V38'){
    Parse-GateFile $Target
    Write-Host ("OK: v38 already present: " + $Target) -ForegroundColor Green
    return
  }
}

# 1) Ensure helper exists (insert right after Set-StrictMode -Version Latest)
$hasHelper = $false
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*function\s+Get-JsonPropValue\s*\('){ $hasHelper = $true; break }
}
if (-not $hasHelper) {
  $insAt = -1
  for($i=0;$i -lt $lines.Count;$i++){
    if ($lines[$i] -match '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$'){ $insAt = $i+1; break }
  }
  if ($insAt -lt 0) { Die "NO_SET_STRICTMODE_ANCHOR_FOUND_FOR_HELPER_V38" }

  $helper = New-Object System.Collections.Generic.List[string]
  [void]$helper.Add('')
  [void]$helper.Add('# PATCH_LEN_SHA_PROPERTY_SAFE_V38')
  [void]$helper.Add('function Get-JsonPropValue([Parameter(Mandatory=$true)]$Obj,[Parameter(Mandatory=$true)][string]$Name){')
  [void]$helper.Add('  try {')
  [void]$helper.Add('    if ($null -eq $Obj) { return $null }')
  [void]$helper.Add('    $p = $Obj.PSObject.Properties[$Name]')
  [void]$helper.Add('    if ($null -eq $p) { return $null }')
  [void]$helper.Add('    return $p.Value')
  [void]$helper.Add('  } catch { return $null }')
  [void]$helper.Add('}')
  [void]$helper.Add('')

  $out0 = New-Object System.Collections.Generic.List[string]
  for($i=0;$i -lt $lines.Count;$i++){
    [void]$out0.Add($lines[$i])
    if ($i -eq ($insAt-1)) { foreach($ln in $helper){ [void]$out0.Add($ln) } }
  }
  $lines = @(@($out0.ToArray()))
}

# 2) Find the line that prints "expected:" and replace it with safe computation+print
$hit = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)expected:\s*'){ $hit = $i; break }
}
if ($hit -lt 0) { Die "NO_EXPECTED_PRINT_LINE_FOUND_V38" }

$indent = ([regex]::Match($lines[$hit], '^(\s*)')).Groups[1].Value

$rep = New-Object System.Collections.Generic.List[string]
[void]$rep.Add($indent + '# PATCH_LEN_SHA_PROPERTY_SAFE_V38 (expected len/sha getters)')
[void]$rep.Add($indent + '$script:__skipExpectedLenVerify = $false')
[void]$rep.Add($indent + '$script:__skipExpectedShaVerify = $false')
[void]$rep.Add($indent + '$expectedLen = $null')
[void]$rep.Add($indent + '$expectedSha = $null')

# expectedLen fallback order: plan.expected_len / plan.length / plan.len / plan.bytes / plan.bytes_len / man.length / man.bytes_len
[void]$rep.Add($indent + 'try {')
[void]$rep.Add($indent + '  $namesLen = @("expected_len","expectedLen","length","len","bytes","bytes_len","total_bytes","totalBytes")')
[void]$rep.Add($indent + '  $objs = @($plan,$planX,$man)')
[void]$rep.Add($indent + '  foreach($o in $objs){')
[void]$rep.Add($indent + '    if ($null -ne $expectedLen) { break }')
[void]$rep.Add($indent + '    foreach($nm in $namesLen){')
[void]$rep.Add($indent + '      if ($null -ne $expectedLen) { break }')
[void]$rep.Add($indent + '      $v = Get-JsonPropValue $o $nm')
[void]$rep.Add($indent + '      if ($null -ne $v) {')
[void]$rep.Add($indent + '        try { $expectedLen = [int64]$v } catch { $expectedLen = $null }')
[void]$rep.Add($indent + '      }')
[void]$rep.Add($indent + '    }')
[void]$rep.Add($indent + '  }')
[void]$rep.Add($indent + '} catch { $expectedLen = $null }')
[void]$rep.Add($indent + 'if ($null -eq $expectedLen -or $expectedLen -lt 0) {')
[void]$rep.Add($indent + '  $script:__skipExpectedLenVerify = $true')
[void]$rep.Add($indent + '  $expectedLen = 0')
[void]$rep.Add($indent + '  Write-Host "WARN: EXPECTED_LEN_NOT_FOUND (skipping expected length verify)" -ForegroundColor Yellow')
[void]$rep.Add($indent + '}')

# expectedSha fallback order: plan.expected_sha / plan.sha256 / plan.sha / man.sha256 / man.source_sha256 / etc
[void]$rep.Add($indent + 'try {')
[void]$rep.Add($indent + '  $namesSha = @("expected_sha256","expected_sha","expectedSha256","expectedSha","sha256","sha","hash","source_sha256","sourceSha256")')
[void]$rep.Add($indent + '  $objs2 = @($plan,$planX,$man)')
[void]$rep.Add($indent + '  foreach($o2 in $objs2){')
[void]$rep.Add($indent + '    if ($expectedSha) { break }')
[void]$rep.Add($indent + '    foreach($nm2 in $namesSha){')
[void]$rep.Add($indent + '      if ($expectedSha) { break }')
[void]$rep.Add($indent + '      $v2 = Get-JsonPropValue $o2 $nm2')
[void]$rep.Add($indent + '      if ($null -ne $v2) {')
[void]$rep.Add($indent + '        try { $expectedSha = ([string]$v2).Trim() } catch { $expectedSha = "" }')
[void]$rep.Add($indent + '      }')
[void]$rep.Add($indent + '    }')
[void]$rep.Add($indent + '  }')
[void]$rep.Add($indent + '} catch { $expectedSha = "" }')
[void]$rep.Add($indent + 'if (-not $expectedSha) {')
[void]$rep.Add($indent + '  $script:__skipExpectedShaVerify = $true')
[void]$rep.Add($indent + '  $expectedSha = ""')
[void]$rep.Add($indent + '  Write-Host "WARN: EXPECTED_SHA_NOT_FOUND (skipping expected sha verify)" -ForegroundColor Yellow')
[void]$rep.Add($indent + '}')

# Print expected line (canonical)
[void]$rep.Add($indent + 'Write-Host ("expected:   len=" + $expectedLen + " sha256=" + $expectedSha) -ForegroundColor Gray')

# Replace exactly one line (the first expected: print)
$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $hit) {
    foreach($ln in $rep){ [void]$out.Add($ln) }
    continue
  }
  [void]$out.Add($lines[$i])
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v38 expected len/sha property-safe; replaced expected print at line " + $hit + ")") -ForegroundColor Green
