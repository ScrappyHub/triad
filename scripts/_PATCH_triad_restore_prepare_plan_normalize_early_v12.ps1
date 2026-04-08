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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v12_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find v7 patched block start
$begin = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*#\s*---\s*patched\s*by\s*_PATCH_triad_restore_prepare_plan_discovery_v7\.ps1\s*---\s*$'){
    $begin = $i; break
  }
}
if ($begin -lt 0) { Die "NO_V7_PATCH_BEGIN_MARKER_FOUND" }

# Find $planObj assignment that pipes to ConvertFrom-Json
$pj = -1
for($i=$begin+1;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*\$planObj\s*=\s*.*ConvertFrom-Json\s*$'){ $pj = $i; break }
  if ($lines[$i] -match '(?im)^\s*#\s*---\s*end\s*patch\s*---\s*$'){ break }
}
if ($pj -lt 0) { Die "NO_PLANOBJ_CONVERTFROMJSON_LINE_FOUND_IN_V7_BLOCK" }

# Idempotent: if our marker already exists in v7 block, do nothing
$already = $false
for($i=$begin;$i -lt [Math]::Min($lines.Count, $begin+250); $i++){
  if ($lines[$i] -match '(?im)^\s*#\s*planobj\s*normalize\s*early:\s*v12\s*$'){
    $already = $true; break
  }
  if ($lines[$i] -match '(?im)^\s*#\s*---\s*end\s*patch\s*---\s*$'){ break }
}
if ($already) {
  Parse-GateFile $Target
  Write-Host ("OK: v12 early normalization already present: " + $Target) -ForegroundColor Green
  return
}

$indent = ([regex]::Match($lines[$pj], '^(\s*)')).Groups[1].Value

# Insert immediately after $planObj = ... ConvertFrom-Json
$ins = New-Object System.Collections.Generic.List[string]
[void]$ins.Add($indent + '# planObj normalize early: v12')
[void]$ins.Add($indent + 'if ($null -eq $planObj) { throw "PLAN_JSON_PARSE_NULL" }')

# blocks normalize
[void]$ins.Add($indent + 'if (-not (Get-Member -InputObject $planObj -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$ins.Add($indent + '  $planObj | Add-Member -MemberType NoteProperty -Name "blocks" -Value @() -Force')
[void]$ins.Add($indent + '}')
[void]$ins.Add($indent + '$planObj.blocks = @(@($planObj.blocks))')

# length normalize (derive from blocks)
[void]$ins.Add($indent + 'if (-not (Get-Member -InputObject $planObj -Name "length" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$ins.Add($indent + '  [int64]$mx = 0')
[void]$ins.Add($indent + '  $bs2 = @(@($planObj.blocks))')
[void]$ins.Add($indent + '  for($k=0;$k -lt $bs2.Count;$k++){')
[void]$ins.Add($indent + '    $b2 = $bs2[$k]')
[void]$ins.Add($indent + '    if ($null -eq $b2) { continue }')
[void]$ins.Add($indent + '    $mOff2 = (Get-Member -InputObject $b2 -Name "offset" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)')
[void]$ins.Add($indent + '    $mLen2 = (Get-Member -InputObject $b2 -Name "length" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)')
[void]$ins.Add($indent + '    if ($mOff2 -and $mLen2) {')
[void]$ins.Add($indent + '      try {')
[void]$ins.Add($indent + '        [int64]$off2 = $b2.offset')
[void]$ins.Add($indent + '        [int64]$ln2  = $b2.length')
[void]$ins.Add($indent + '        [int64]$end2 = $off2 + $ln2')
[void]$ins.Add($indent + '        if ($end2 -gt $mx) { $mx = $end2 }')
[void]$ins.Add($indent + '      } catch { }')
[void]$ins.Add($indent + '    }')
[void]$ins.Add($indent + '  }')
[void]$ins.Add($indent + '  $planObj | Add-Member -MemberType NoteProperty -Name "length" -Value $mx -Force')
[void]$ins.Add($indent + '  Remove-Variable -Name mx -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '}')

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  [void]$out.Add($lines[$i])
  if ($i -eq $pj) {
    foreach($ln in $ins){ [void]$out.Add($ln) }
  }
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (inserted early planObj normalization after line index " + $pj + ")") -ForegroundColor Green
