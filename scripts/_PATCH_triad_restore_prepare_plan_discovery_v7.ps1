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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v7_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Locate v6 block markers
$begin = -1
$end = -1
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*#\s*---\s*patched\s*by\s*_PATCH_triad_restore_prepare_planpath_v6\.ps1\s*---\s*$'){ $begin=$i; break }
}
if ($begin -lt 0) { Die "NO_V6_PATCH_BEGIN_MARKER_FOUND" }
for($i=$begin+1;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*#\s*---\s*end\s*patch\s*---\s*$'){ $end=$i; break }
}
if ($end -lt 0) { Die "NO_V6_PATCH_END_MARKER_FOUND" }

$indent = ([regex]::Match($lines[$begin], '^(\s*)')).Groups[1].Value

# v7: pass the real OutFile to tree_prepare; discover plan file by prefix match
$blk = New-Object System.Collections.Generic.List[string]
[void]$blk.Add($indent + '# --- patched by _PATCH_triad_restore_prepare_plan_discovery_v7.ps1 ---')
[void]$blk.Add($indent + '$outParent = Split-Path -Parent $OutFile')
[void]$blk.Add($indent + 'if ($outParent -and -not (Test-Path -LiteralPath $outParent -PathType Container)) { New-Item -ItemType Directory -Force -Path $outParent | Out-Null }')
[void]$blk.Add($indent + '$outLeaf = Split-Path -Leaf $OutFile')
[void]$blk.Add($indent + '$null = (& $TreePrep -RepoRoot $RepoRoot -SnapshotDir $SnapshotDir -OutFile $OutFile -ManifestPath $ManifestPath)')
[void]$blk.Add($indent + '$pattern = ($outLeaf + ".triad_plan_tree_v1_*.json")')
[void]$blk.Add($indent + '$cand = Get-ChildItem -LiteralPath $outParent -File -Filter $pattern -ErrorAction Stop | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1')
[void]$blk.Add($indent + 'if ($null -eq $cand) { throw ("MISSING_PLAN_OUTFILE: " + (Join-Path $outParent $pattern)) }')
[void]$blk.Add($indent + '$PlanPath = $cand.FullName')
[void]$blk.Add($indent + '$planObj = Get-Content -Raw -LiteralPath $PlanPath -Encoding UTF8 | ConvertFrom-Json')
[void]$blk.Add($indent + 'if ($null -eq $planObj) { throw "PLAN_JSON_PARSE_NULL" }')
[void]$blk.Add($indent + 'if (-not (Get-Member -InputObject $planObj -Name "blocks" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$blk.Add($indent + '  $planObj | Add-Member -MemberType NoteProperty -Name "blocks" -Value @() -Force')
[void]$blk.Add($indent + '}')
[void]$blk.Add($indent + '$planObj.blocks = @(@($planObj.blocks))')
[void]$blk.Add($indent + '$planObj | Add-Member -MemberType NoteProperty -Name "plan_path" -Value $PlanPath -Force')
[void]$blk.Add($indent + 'return $planObj')
[void]$blk.Add($indent + '# --- end patch ---')

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $begin) {
    foreach($ln in $blk){ [void]$out.Add($ln) }
    $i = $end
    continue
  }
  [void]$out.Add($lines[$i])
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (replaced v6 block lines " + $begin + ".." + $end + ")") -ForegroundColor Green
