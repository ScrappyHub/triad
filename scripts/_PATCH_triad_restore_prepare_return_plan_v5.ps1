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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v5_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$RestorePrepPath = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $RestorePrepPath -PathType Leaf)) { Die ("MISSING_RESTORE_PREP: " + $RestorePrepPath) }
Copy-Item -LiteralPath $RestorePrepPath -Destination (Join-Path $BackupDir ((Split-Path -Leaf $RestorePrepPath) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $RestorePrepPath -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find the injected return line from v4:
#   return (& $TreePrep -RepoRoot ... -SnapshotDir ... -OutFile ... -ManifestPath ...)
$hit = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*return\s*\(\s*&\s*\$TreePrep\b'){ $hit=$i; break }
}
if ($hit -lt 0) { Die "RESTORE_PREP_NO_INJECTED_RETURN_AMP_TREEPREP_FOUND" }

$indent = ([regex]::Match($lines[$hit], '^(\s*)')).Groups[1].Value

# Replace that single return line with a block that returns the parsed plan JSON
$block = New-Object System.Collections.Generic.List[string]
[void]$block.Add($indent + '# --- patched by _PATCH_triad_restore_prepare_return_plan_v5.ps1 ---')
[void]$block.Add($indent + '$null = (& $TreePrep -RepoRoot $RepoRoot -SnapshotDir $SnapshotDir -OutFile $OutFile -ManifestPath $ManifestPath)')
[void]$block.Add($indent + 'if (-not (Test-Path -LiteralPath $OutFile -PathType Leaf)) { throw ("MISSING_PLAN_OUTFILE: " + $OutFile) }')
[void]$block.Add($indent + '$planObj = Get-Content -Raw -LiteralPath $OutFile -Encoding UTF8 | ConvertFrom-Json')
[void]$block.Add($indent + 'if ($null -eq $planObj) { throw "PLAN_JSON_PARSE_NULL" }')
[void]$block.Add($indent + 'if (-not (Get-Member -InputObject $planObj -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$block.Add($indent + '  $planObj | Add-Member -MemberType NoteProperty -Name "blocks" -Value @() -Force')
[void]$block.Add($indent + '}')
[void]$block.Add($indent + '$planObj.blocks = @(@($planObj.blocks))')
[void]$block.Add($indent + 'return $planObj')
[void]$block.Add($indent + '# --- end patch ---')

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $hit) {
    foreach($ln in $block){ [void]$out.Add($ln) }
  } else {
    [void]$out.Add($lines[$i])
  }
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $RestorePrepPath $final
Parse-GateFile $RestorePrepPath
Write-Host ("FINAL_OK: patched " + $RestorePrepPath + " (replaced injected return at line index " + $hit + ")") -ForegroundColor Green
