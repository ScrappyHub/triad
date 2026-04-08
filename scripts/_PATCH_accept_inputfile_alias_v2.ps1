param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  if ([string]::IsNullOrWhiteSpace($Path)) { Die "WRITE_UTF8_PATH_EMPTY" }
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateFile([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSEGATE_MISSING: " + $Path) }; $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8; $null = [ScriptBlock]::Create($raw) }

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die ("MISSING_REPO: " + $RepoRoot) }
$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_inputfile_alias_v2_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$files = Get-ChildItem -LiteralPath $ScriptsDir -File -Filter "*.ps1" -Force
$changed = New-Object System.Collections.Generic.List[string]

foreach($f in $files){
  $p = $f.FullName
  $raw = Get-Content -Raw -LiteralPath $p -Encoding UTF8
  $txt = $raw.Replace("`r`n","`n").Replace("`r","`n")

  # Only patch scripts that (a) declare InputPath, (b) do NOT declare InputFile, (c) do NOT already alias InputFile
  if ($txt -notmatch '\$\bInputPath\b') { continue }
  if ($txt -match '\$\bInputFile\b') { continue }
  if ($txt -match 'Alias\(\s*["']InputFile["']\s*\)') { continue }

  $lines = @(@($txt -split "`n",-1))

  # Find a param(...) block and the specific line that declares only $InputPath
  $start = -1; $end = -1
  for($i=0;$i -lt $lines.Count;$i++){ if ($lines[$i] -match '^\s*param\s*\('){ $start=$i; break } }
  if ($start -lt 0) { continue }
  for($i=$start+1;$i -lt $lines.Count;$i++){ if ($lines[$i] -match '^\s*\)\s*$'){ $end=$i; break } }
  if ($end -lt 0) { continue }

  $idx = -1
  for($i=$start+1;$i -lt $end;$i++){
    if ($lines[$i] -match '\$\bInputPath\b') {
      $varCount = ([regex]::Matches($lines[$i],'\$\w+' )).Count
      if ($varCount -eq 1) { $idx=$i; break }
    }
  }
  if ($idx -lt 0) { continue }

  $indent = ([regex]::Match($lines[$idx], '^(\s*)')).Groups[1].Value
  $out = New-Object System.Collections.Generic.List[string]
  for($i=0;$i -lt $lines.Count;$i++){
    if ($i -eq $idx) { [void]$out.Add($indent + '[Alias("InputFile")]') }
    [void]$out.Add($lines[$i])
  }
  $txt2 = ($out.ToArray() -join "`n")

  Copy-Item -LiteralPath $p -Destination (Join-Path $BackupDir ((Split-Path -Leaf $p) + ".pre_alias")) -Force
  Write-Utf8NoBomLf $p $txt2
  Parse-GateFile $p
  $changed.Add($p) | Out-Null
}

Write-Host ("PATCH_DONE: alias added in {0} file(s)" -f $changed.Count) -ForegroundColor Green
foreach($c in $changed){ Write-Host ("  CHANGED: " + $c) -ForegroundColor Cyan }
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray
