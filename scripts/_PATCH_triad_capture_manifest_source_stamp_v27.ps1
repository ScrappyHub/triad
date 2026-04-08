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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_capture_v27_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_capture_tree_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
$lines = @(@($txt -split "`n",-1))

# Idempotency
for($i=0;$i -lt $lines.Count;$i++){
  if ($lines[$i] -match '(?im)^\s*#\s*PATCH_MAN_SOURCE_STAMP_V27\s*$'){
    Parse-GateFile $Target
    Write-Host ("OK: v27 already present: " + $Target) -ForegroundColor Green
    return
  }
}

function Find-AnchorIndex([string[]]$arr){
  # 1) ConvertTo-Json used to serialize $man
  for($i=0;$i -lt $arr.Count;$i++){
    $ln = $arr[$i]
    if ($ln -match '(?im)ConvertTo-Json' -and $ln -match '(?im)\$man\b'){ return $i }
  }
  # 2) To-CanonJson style serializer with $man
  for($i=0;$i -lt $arr.Count;$i++){
    $ln = $arr[$i]
    if ($ln -match '(?im)To-CanonJson' -and $ln -match '(?im)\$man\b'){ return $i }
  }
  # 3) A write call that mentions manifest.json or ManifestPath
  for($i=0;$i -lt $arr.Count;$i++){
    $ln = $arr[$i]
    if ($ln -match '(?im)(manifest\.json|\$ManifestPath|\bManifestPath\b)' -and
        $ln -match '(?im)(WriteAllText|Set-Content|Out-File|Write-Utf8|Write-File|WriteAll)'){
      return $i
    }
  }
  return -1
}

$ix = Find-AnchorIndex $lines
if ($ix -lt 0) {
  # give a deterministic hint block in the error text (no interactive printing required)
  $hits = New-Object System.Collections.Generic.List[string]
  for($i=0;$i -lt $lines.Count;$i++){
    if ($lines[$i] -match '(?im)manifest\.json|\bManifestPath\b|ConvertTo-Json|To-CanonJson|WriteAllText|Set-Content'){
      $hits.Add(("{0:D4}: {1}" -f $i, $lines[$i]))
      if ($hits.Count -ge 25) { break }
    }
  }
  $msg = "NO_MANIFEST_SERIALIZE_ANCHOR_FOUND_V27. FirstHits=`n" + ($hits.ToArray() -join "`n")
  Die $msg
}

$indent = ([regex]::Match($lines[$ix], '^(\s*)')).Groups[1].Value

$ins = New-Object System.Collections.Generic.List[string]
[void]$ins.Add($indent + '# PATCH_MAN_SOURCE_STAMP_V27')
[void]$ins.Add($indent + '# Ensure manifest.source.{name,length,sha256} is present when capturing from a file.')
[void]$ins.Add($indent + 'try {')
[void]$ins.Add($indent + '  $__src = $null')
[void]$ins.Add($indent + '  $names = @("InFile","InputFile","InputPath","SourcePath","SrcPath","Path")')
[void]$ins.Add($indent + '  for($k=0;$k -lt $names.Count -and $null -eq $__src; $k++){')
[void]$ins.Add($indent + '    $__v = Get-Variable -Name $names[$k] -Scope Local -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '    if ($null -ne $__v -and $null -ne $__v.Value) {')
[void]$ins.Add($indent + '      $p0 = [string]$__v.Value')
[void]$ins.Add($indent + '      if ($p0 -and (Test-Path -LiteralPath $p0 -PathType Leaf)) { $__src = $p0 }')
[void]$ins.Add($indent + '    }')
[void]$ins.Add($indent + '  }')
[void]$ins.Add($indent + '  if ($null -ne $__src) {')
[void]$ins.Add($indent + '    if (-not (Get-Member -InputObject $man -Name "source" -MemberType NoteProperty,Property -ErrorAction SilentlyContinue)) {')
[void]$ins.Add($indent + '      $srcObj = New-Object PSObject')
[void]$ins.Add($indent + '      $man | Add-Member -MemberType NoteProperty -Name "source" -Value $srcObj -Force')
[void]$ins.Add($indent + '    }')
[void]$ins.Add($indent + '    if ($null -eq $man.source) { $man.source = (New-Object PSObject) }')
[void]$ins.Add($indent + '    $fi = Get-Item -LiteralPath $__src -ErrorAction Stop')
[void]$ins.Add($indent + '    [int64]$len = $fi.Length')
[void]$ins.Add($indent + '    $nm = Split-Path -Leaf $__src')
[void]$ins.Add($indent + '    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $__src).Hash.ToLowerInvariant()')
[void]$ins.Add($indent + '    $man.source | Add-Member -MemberType NoteProperty -Name "name" -Value $nm -Force')
[void]$ins.Add($indent + '    $man.source | Add-Member -MemberType NoteProperty -Name "length" -Value $len -Force')
[void]$ins.Add($indent + '    $man.source | Add-Member -MemberType NoteProperty -Name "sha256" -Value $h -Force')
[void]$ins.Add($indent + '    $man.source | Add-Member -MemberType NoteProperty -Name "path" -Value $__src -Force')
[void]$ins.Add($indent + '    Remove-Variable -Name fi -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '    Remove-Variable -Name len -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '    Remove-Variable -Name nm -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '    Remove-Variable -Name h -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '  }')
[void]$ins.Add($indent + '  Remove-Variable -Name __src -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '  Remove-Variable -Name __v -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '  Remove-Variable -Name names -ErrorAction SilentlyContinue')
[void]$ins.Add($indent + '} catch { }')

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if ($i -eq $ix) { foreach($ln in $ins){ [void]$out.Add($ln) } }
  [void]$out.Add($lines[$i])
}

$final = ($out.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $final
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v27 inserted manifest.source stamp before anchor line " + $ix + ")") -ForegroundColor Green
