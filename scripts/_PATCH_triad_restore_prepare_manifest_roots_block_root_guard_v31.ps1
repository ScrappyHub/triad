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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v31_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find the exact failing line: $expectedRoot = [string]$man.roots.block_root
$hit = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*\$expectedRoot\s*=\s*\[string\]\s*\$man\.roots\.block_root\s*$'){ $hit = $i; break }
}
if ($hit -lt 0) { Die "NO_MAN_ROOTS_BLOCK_ROOT_LINE_FOUND" }

# Idempotency
for($j=[Math]::Max(0,$hit-2); $j -le [Math]::Min($hit+8,$lines.Count-1); $j++){
  if ($lines[$j] -match '(?im)PATCH_EXPECTEDROOT_GUARD_V31'){ 
    Parse-GateFile $Target
    Write-Host ("OK: v31 already present: " + $Target) -ForegroundColor Green
    return
  }
}

$indent = ([regex]::Match($lines[$hit], '^(\s*)')).Groups[1].Value

$rep = New-Object System.Collections.Generic.List[string]
[void]$rep.Add($indent + '# PATCH_EXPECTEDROOT_GUARD_V31')
[void]$rep.Add($indent + '$expectedRoot = ""')
[void]$rep.Add($indent + 'try {')
[void]$rep.Add($indent + '  # Prefer manifest.roots.block_root if present')
[void]$rep.Add($indent + '  $pRoots = $man.PSObject.Properties["roots"]')
[void]$rep.Add($indent + '  if ($null -ne $pRoots -and $null -ne $pRoots.Value) {')
[void]$rep.Add($indent + '    $r = $pRoots.Value')
[void]$rep.Add($indent + '    $pBr = $r.PSObject.Properties["block_root"]')
[void]$rep.Add($indent + '    if ($null -ne $pBr -and $null -ne $pBr.Value) { $expectedRoot = [string]$pBr.Value }')
[void]$rep.Add($indent + '  }')
[void]$rep.Add($indent + '} catch { $expectedRoot = "" }')
[void]$rep.Add($indent + 'if (-not $expectedRoot) {')
[void]$rep.Add($indent + '  # Fallback: flat manifest.block_root')
[void]$rep.Add($indent + '  try {')
[void]$rep.Add($indent + '    $pBr2 = $man.PSObject.Properties["block_root"]')
[void]$rep.Add($indent + '    if ($null -ne $pBr2 -and $null -ne $pBr2.Value) { $expectedRoot = [string]$pBr2.Value }')
[void]$rep.Add($indent + '  } catch { $expectedRoot = "" }')
[void]$rep.Add($indent + '}')
[void]$rep.Add($indent + 'if (-not $expectedRoot) { throw "MANIFEST_MISSING_BLOCK_ROOT_V31" }')
[void]$rep.Add($indent + 'Remove-Variable -Name pRoots -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + 'Remove-Variable -Name r -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + 'Remove-Variable -Name pBr -ErrorAction SilentlyContinue')
[void]$rep.Add($indent + 'Remove-Variable -Name pBr2 -ErrorAction SilentlyContinue')

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
Write-Host ("FINAL_OK: patched " + $Target + " (v31 guarded manifest roots.block_root -> fallback manifest.block_root; line=" + $hit + ")") -ForegroundColor Green
