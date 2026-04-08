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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_capture_v33_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_capture_tree_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Idempotency: if marker already present, do nothing.
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*#\s*PATCH_MAN_ROOTS_STAMP_V33\s*$'){
    Parse-GateFile $Target
    Write-Host ("OK: v33 already present: " + $Target) -ForegroundColor Green
    return
  }
}

# Anchor: same idea as v27 — line that writes manifest.json (any Write-... manifest.json)
$ix = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)manifest\.json'){ 
    if ($lines[$i] -match '(?im)Write-.*manifest\.json'){ $ix = $i; break }
  }
}
if ($ix -lt 0) { Die "NO_MANIFEST_WRITE_ANCHOR_FOUND_V33" }

$indent = ([regex]::Match($lines[$ix], '^(\s*)')).Groups[1].Value

$ins = New-Object System.Collections.Generic.List[string]
[void]$ins.Add($indent + '# PATCH_MAN_ROOTS_STAMP_V33')
[void]$ins.Add($indent + '# Persist semantic_root + block_root into manifest for restore_prepare readers.')
[void]$ins.Add($indent + 'try {')
[void]$ins.Add($indent + '  $__br = ""')
[void]$ins.Add($indent + '  $__sr = ""')

# discover block_root
[void]$ins.Add($indent + '  $brNames = @("block_root","blockRoot","BlockRoot","BlockRootHex")')
[void]$ins.Add($indent + '  for($k=0;$k -lt $brNames.Count -and -not $__br; $k++){')
[void]$ins.Add($indent + '    $__v = Get-Variable -Name $brNames[$k] -Scope Local -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '    if ($null -ne $__v -and $null -ne $__v.Value) { try { $__br = [string]$__v.Value } catch { $__br = "" } }')
[void]$ins.Add($indent + '  }')

# discover semantic_root
[void]$ins.Add($indent + '  $srNames = @("semantic_root","semanticRoot","SemanticRoot","SemanticRootHex")')
[void]$ins.Add($indent + '  for($k=0;$k -lt $srNames.Count -and -not $__sr; $k++){')
[void]$ins.Add($indent + '    $__v2 = Get-Variable -Name $srNames[$k] -Scope Local -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '    if ($null -ne $__v2 -and $null -ne $__v2.Value) { try { $__sr = [string]$__v2.Value } catch { $__sr = "" } }')
[void]$ins.Add($indent + '  }')

# ensure man.roots exists
[void]$ins.Add($indent + '  if (-not (Get-Member -InputObject $man -Name "roots" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$ins.Add($indent + '    $man | Add-Member -MemberType NoteProperty -Name "roots" -Value (New-Object PSObject) -Force')
[void]$ins.Add($indent + '  }')
[void]$ins.Add($indent + '  if ($null -eq $man.roots) { $man.roots = (New-Object PSObject) }')

# stamp values
[void]$ins.Add($indent + '  if ($__br) {')
[void]$ins.Add($indent + '    $man.roots | Add-Member -MemberType NoteProperty -Name "block_root" -Value $__br -Force')
[void]$ins.Add($indent + '    $man | Add-Member -MemberType NoteProperty -Name "block_root" -Value $__br -Force')
[void]$ins.Add($indent + '  }')
[void]$ins.Add($indent + '  if ($__sr) {')
[void]$ins.Add($indent + '    $man.roots | Add-Member -MemberType NoteProperty -Name "semantic_root" -Value $__sr -Force')
[void]$ins.Add($indent + '    $man | Add-Member -MemberType NoteProperty -Name "semantic_root" -Value $__sr -Force')
[void]$ins.Add($indent + '  }')

# cleanup
[void]$ins.Add($indent + '  Remove-Variable -Name __br -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '  Remove-Variable -Name __sr -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '  Remove-Variable -Name brNames -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '  Remove-Variable -Name srNames -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '  Remove-Variable -Name __v -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '  Remove-Variable -Name __v2 -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '} catch { }')

# insert before manifest write
$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $ix) { foreach($ln in $ins){ [void]$out.Add($ln) } }
  [void]$out.Add($lines[$i])
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v33 stamped man.roots.{block_root,semantic_root} before manifest write; anchorLine=" + $ix + ")") -ForegroundColor Green
