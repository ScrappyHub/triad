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
function Sha256HexOfFile([string]$p){
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw ("MISSING_FILE_FOR_SHA256: " + $p) }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [System.IO.File]::Open($p,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::Read)
    try {
      $hash = $sha.ComputeHash($fs)
    } finally {
      $fs.Dispose()
    }
  } finally {
    $sha.Dispose()
  }
  $sb = New-Object System.Text.StringBuilder
  for($i=0;$i -lt $hash.Length;$i++){
    [void]$sb.Append($hash[$i].ToString("x2"))
  }
  return $sb.ToString()
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_prepare_v24_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_prepare_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Find the exact line: $expectedSha = [string]$man.source.sha256
$hits = New-Object System.Collections.Generic.List[int]
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*\$expectedSha\s*=\s*\[string\]\$man\.source\.sha256\s*$') { [void]$hits.Add($i) }
}
if ($hits.Count -lt 1) { Die "NO_EXPECTEDSHA_LINE_FOUND" }

# Replace all occurrences (idempotent/safe)
for($h=0;$h -lt $hits.Count;$h++){
  $ix = $hits[$h]
  $indent = ([regex]::Match($lines[$ix], '^(\s*)')).Groups[1].Value

  $blk = New-Object System.Collections.Generic.List[string]
  [void]$blk.Add($indent + '# PATCH_MAN_SOURCE_SHA256_GUARD_V24')
  [void]$blk.Add($indent + 'if ($null -eq $man) { throw "MANIFEST_NULL" }')
  [void]$blk.Add($indent + 'if (-not (Get-Member -InputObject $man -Name "source" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
  [void]$blk.Add($indent + '  $src0 = New-Object PSObject')
  [void]$blk.Add($indent + '  $man | Add-Member -MemberType NoteProperty -Name "source" -Value $src0 -Force')
  [void]$blk.Add($indent + '}')
  [void]$blk.Add($indent + 'if ($null -eq $man.source) { $man.source = (New-Object PSObject) }')

  [void]$blk.Add($indent + '$__mSha = (Get-Member -InputObject $man.source -Name "sha256" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)')
  [void]$blk.Add($indent + 'if ($__mSha) {')
  [void]$blk.Add($indent + '  $expectedSha = [string]$man.source.sha256')
  [void]$blk.Add($indent + '} else {')
  [void]$blk.Add($indent + '  # Manifest omits source.sha256; compute from the source file on disk (StrictMode-safe path discovery).')
  [void]$blk.Add($indent + '  $candNames = @("SourcePath","SrcPath","InFile","InputFile","OutFile")')
  [void]$blk.Add($indent + '  $__src = $null')
  [void]$blk.Add($indent + '  for($ci=0;$ci -lt $candNames.Count;$ci++){')
  [void]$blk.Add($indent + '    $vn = $candNames[$ci]')
  [void]$blk.Add($indent + '    $v = Get-Variable -Name $vn -Scope Local -ErrorAction SilentlyContinue')
  [void]$blk.Add($indent + '    if ($null -ne $v -and $null -ne $v.Value) {')
  [void]$blk.Add($indent + '      try {')
  [void]$blk.Add($indent + '        $p = [string]$v.Value')
  [void]$blk.Add($indent + '        if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { $__src = $p; break }')
  [void]$blk.Add($indent + '      } catch { }')
  [void]$blk.Add($indent + '    }')
  [void]$blk.Add($indent + '  }')
  [void]$blk.Add($indent + '  if ($null -eq $__src) { throw "SOURCE_PATH_DISCOVERY_FAILED_FOR_SHA256_V24" }')
  [void]$blk.Add($indent + '  $sha = Sha256HexOfFile $__src')
  [void]$blk.Add($indent + '  $man.source | Add-Member -MemberType NoteProperty -Name "sha256" -Value $sha -Force')
  [void]$blk.Add($indent + '  $expectedSha = [string]$sha')
  [void]$blk.Add($indent + '  Remove-Variable -Name sha -ErrorAction SilentlyContinue')
  [void]$blk.Add($indent + '  Remove-Variable -Name __src -ErrorAction SilentlyContinue')
  [void]$blk.Add($indent + '  Remove-Variable -Name candNames -ErrorAction SilentlyContinue')
  [void]$blk.Add($indent + '}')
  [void]$blk.Add($indent + 'Remove-Variable -Name __mSha -ErrorAction SilentlyContinue')

  # splice line -> block
  $pre = @()
  if ($ix -gt 0) { $pre = $lines[0..($ix-1)] }
  $post = @()
  if ($ix -lt ($lines.Count-1)) { $post = $lines[($ix+1)..($lines.Count-1)] }
  $lines = @(@($pre) + @($blk.ToArray()) + @($post))

  # adjust remaining hit indices
  $delta = ($blk.Count - 1)
  for($k=$h+1; $k -lt $hits.Count; $k++){
    $hits[$k] = $hits[$k] + $delta
  }
}

$final = ($lines -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (guarded man.source.sha256 -> expectedSha; hits=" + $hits.Count + ")") -ForegroundColor Green
