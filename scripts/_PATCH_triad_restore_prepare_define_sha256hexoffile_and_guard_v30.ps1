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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v30_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# -----------------------------
# 1) Ensure function Sha256HexOfFile exists (idempotent insert)
# -----------------------------
$hasFn = $false
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*function\s+Sha256HexOfFile\s*\('){ $hasFn = $true; break }
}

if (-not $hasFn) {
  # Anchor: first Set-StrictMode line (insert right after)
  $insAt = -1
  for($i=0;$i -lt $lines.Count;$i++){
    if ($lines[$i] -match '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$'){ $insAt = $i+1; break }
  }
  if ($insAt -lt 0) { Die "NO_SET_STRICTMODE_ANCHOR_FOUND_FOR_FN_INSERT" }

  $indent0 = ""
  $fn = New-Object System.Collections.Generic.List[string]
  [void]$fn.Add('')
  [void]$fn.Add('# PATCH_DEFINE_SHA256HEXOFFILE_V30')
  [void]$fn.Add('function Sha256HexOfFile([Parameter(Mandatory=$true)][string]$Path){')
  [void]$fn.Add('  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path -ErrorAction Stop).Hash')
  [void]$fn.Add('  if ($null -eq $h) { return "" }')
  [void]$fn.Add('  return ([string]$h).ToLowerInvariant()')
  [void]$fn.Add('}')
  [void]$fn.Add('')

  $out0 = New-Object System.Collections.Generic.List[string]
  for($i=0;$i -lt $lines.Count;$i++){
    [void]$out0.Add($lines[$i])
    if ($i -eq ($insAt-1)) {
      foreach($ln in $fn){ [void]$out0.Add($ln) }
    }
  }
  $lines = @(@($out0.ToArray()))
}

# -----------------------------
# 2) Guard the call site: "$sha = Sha256HexOfFile $__src"
#    so it does NOT run when $script:__skipSourceShaVerify is true
# -----------------------------
$hit = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*\$sha\s*=\s*Sha256HexOfFile\s+\$__src\s*$'){ $hit = $i; break }
}
if ($hit -lt 0) { Die "NO_SHA256HEXOFFILE_CALLSITE_FOUND" }

# Idempotent: if we already replaced it with our marker, exit
for($j=[Math]::Max(0,$hit-2); $j -le [Math]::Min($hit+2,$lines.Count-1); $j++){
  if ($lines[$j] -match '(?im)PATCH_GUARD_SHA256HEXOFFILE_CALL_V30'){ 
    Parse-GateFile $Target
    Write-Host ("OK: v30 guard already present: " + $Target) -ForegroundColor Green
    return
  }
}

$indent = ([regex]::Match($lines[$hit], '^(\s*)')).Groups[1].Value

$rep = New-Object System.Collections.Generic.List[string]
[void]$rep.Add($indent + '# PATCH_GUARD_SHA256HEXOFFILE_CALL_V30')
[void]$rep.Add($indent + 'if (-not $script:__skipSourceShaVerify) {')
[void]$rep.Add($indent + '  $sha = Sha256HexOfFile $__src')
[void]$rep.Add($indent + '} else {')
[void]$rep.Add($indent + '  $sha = ""')
[void]$rep.Add($indent + '}')

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
Write-Host ("FINAL_OK: patched " + $Target + " (v30 defined Sha256HexOfFile if missing; guarded callsite at line " + $hit + ")") -ForegroundColor Green
