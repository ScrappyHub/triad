param([Parameter(Mandatory=$true)][string]$LibPath,[Parameter(Mandatory=$false)][string]$RepoRoot="")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Utf8NoBom { New-Object System.Text.UTF8Encoding($false) }
function WriteUtf8NoBomLf([string]$Path,[string]$Content){
  $lf = $Content.Replace("`r`n","`n")
  if(-not $lf.EndsWith("`n")){ $lf += "`n" }
  [IO.File]::WriteAllText($Path,$lf,(Utf8NoBom))
}

function Try-Parse([string]$Text){
  try { [ScriptBlock]::Create($Text) | Out-Null; return $true } catch { return $false }
}

function Minimal-Fix([string]$Text){
  # Fix the exact corruption you are seeing: line-start "} | Sort-Object" should be ") | Sort-Object"
  $t = $Text.Replace("`r`n","`n")
  $t = [System.Text.RegularExpressions.Regex]::Replace(
         $t,
         '(?m)^(\s*)\}\s*\|\s*Sort-Object\b',
         '$1) | Sort-Object')
  return $t
}

function Find-BlockRange {
  param([Parameter(Mandatory=$true)][string]$Text,[Parameter(Mandatory=$true)][string]$Needle)
  $start = $Text.IndexOf($Needle, [System.StringComparison]::Ordinal)
  if($start -lt 0){ return $null }
  $open = $Text.IndexOf("{", $start)
  if($open -lt 0){ Die ("BLOCK_FAIL: no '{' after needle: " + $Needle) }
  $depth = 0
  for($i=$open; $i -lt $Text.Length; $i++){
    $ch = $Text[$i]
    if($ch -eq "{"){ $depth++ }
    elseif($ch -eq "}"){
      $depth--
      if($depth -eq 0){ return [pscustomobject]@{ Start=$start; End=$i } }
    }
  }
  Die ("BLOCK_FAIL: unterminated braces for needle: " + $Needle)
}

if(-not (Test-Path -LiteralPath $LibPath)){ Die ("MISSING_LIB: " + $LibPath) }

$dir = Split-Path -Parent $LibPath
$name = Split-Path -Leaf $LibPath

# Gather candidates: current lib + all backups, newest first
$candidates = New-Object System.Collections.Generic.List[object]
$candidates.Add([pscustomobject]@{ Path=$LibPath; Kind="current" })
$baks = Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like ($name + ".bak_*") }
if($baks){
  foreach($b in ($baks | Sort-Object LastWriteTimeUtc -Descending)){
    $candidates.Add([pscustomobject]@{ Path=$b.FullName; Kind="backup" })
  }
}

# Choose first candidate that parses after minimal fix
$chosenPath = $null
$chosenText = $null
foreach($c in $candidates){
  $txt = Get-Content -LiteralPath $c.Path -Raw -Encoding UTF8
  $txt = Minimal-Fix $txt
  if(Try-Parse $txt){
    $chosenPath = $c.Path
    $chosenText = $txt
    break
  }
}

if(-not $chosenText){
  Die "RESCUE_FAIL: no candidate (current or backups) parses even after minimal fix. We need a clean upstream copy."
}

# Write chosen baseline into lib (normalized + minimally fixed)
WriteUtf8NoBomLf $LibPath $chosenText

# Backup the baseline we just set (always)
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$bak = $LibPath + ".bak_rescue2_" + $ts
WriteUtf8NoBomLf $bak $chosenText
if(-not (Test-Path -LiteralPath $bak)){ Die ("BACKUP_FAILED: " + $bak) }

# Reload from disk (authoritative)
$raw = Get-Content -LiteralPath $LibPath -Raw -Encoding UTF8
$raw = $raw.Replace("`r`n","`n")

# Locate canon-json functions (must exist)
$r1 = Find-BlockRange -Text $raw -Needle "function ConvertTo-OrderedValue"
$r2 = Find-BlockRange -Text $raw -Needle "function To-CanonJson"
if(-not $r1 -or -not $r2){ Die "RESCUE_FAIL: could not locate canon-json functions after baseline restore" }
if($r2.Start -lt $r1.Start){ $tmp=$r1; $r1=$r2; $r2=$tmp }

# Replacement: PSCustomObject + Add-Member insertion order (no OrderedDictionary)
$replacement = @'
function ConvertTo-OrderedValue($v){
  if($null -eq $v){ return $null }
  if($v -is [string]){ return $v }

  if($v -is [System.Collections.IDictionary]){
    $keys = @()
    foreach($k in $v.Keys){ $keys += [string]$k }
    $keys = @($keys | Sort-Object)
    $o = [pscustomobject]@{}
    foreach($k in $keys){
      $o | Add-Member -MemberType NoteProperty -Name $k -Value (ConvertTo-OrderedValue $v[$k])
    }
    return $o
  }

  if($v -is [System.Collections.IEnumerable]){
    $arr = @()
    foreach($x in $v){ $arr += ,(ConvertTo-OrderedValue $x) }
    return $arr
  }

  if($v -is [psobject]){
    $names = @()
    foreach($mi in $v.PSObject.Properties){
      if($mi -is [System.Management.Automation.PSMemberInfo]){
        if($mi.MemberType -in @("NoteProperty","Property")){ $names += [string]$mi.Name }
      }
    }
    $names = @($names | Sort-Object)
    if($names.Count -gt 0){
      $o = [pscustomobject]@{}
      foreach($n in $names){
        $o | Add-Member -MemberType NoteProperty -Name $n -Value (ConvertTo-OrderedValue ($v.PSObject.Properties[$n].Value))
      }
      return $o
    }
  }
  return $v
}

function To-CanonJson($obj,[int]$Depth=32){
  $canon = ConvertTo-OrderedValue $obj
  return ($canon | ConvertTo-Json -Depth $Depth -Compress)
}
'@

$prefix  = $raw.Substring(0, [int]$r1.Start)
$suffix  = $raw.Substring(([int]$r2.End + 1))
$patched = $prefix.TrimEnd("`n") + "`n`n" + $replacement.TrimEnd("`n") + "`n`n" + $suffix.TrimStart("`n")
WriteUtf8NoBomLf $LibPath $patched

# Parse gate patched lib (must succeed)
[ScriptBlock]::Create((Get-Content -Raw -LiteralPath $LibPath -Encoding UTF8)) | Out-Null
Write-Host "RESCUE_OK: baseline restored (parsable) + minimal-fix applied + canon-json replaced + lib parses" -ForegroundColor Green
Write-Host ("chosen: {0}" -f $chosenPath) -ForegroundColor Cyan
Write-Host ("backup: {0}" -f $bak) -ForegroundColor Cyan
Write-Host ("lib:    {0}" -f $LibPath) -ForegroundColor Cyan

if($RepoRoot -and (Test-Path -LiteralPath $RepoRoot)){
  $diag = Join-Path $RepoRoot "scripts\_diag_neverlost_name_strictmode_v1.ps1"
  if(Test-Path -LiteralPath $diag){
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $diag -Which make_allowed_signers
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $diag -Which show_identity
  }
}
