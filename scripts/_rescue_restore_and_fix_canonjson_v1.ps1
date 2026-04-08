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

# --- restore from latest backup if present ---
$bakPattern = ($LibPath + ".bak_*")
$baks = Get-ChildItem -LiteralPath (Split-Path -Parent $LibPath) -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like $bakPattern }
if($baks -and $baks.Count -gt 0){
  $latest = $baks | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  $raw0 = Get-Content -LiteralPath $latest.FullName -Raw -Encoding UTF8
  $raw0 = $raw0.Replace("`r`n","`n")
  WriteUtf8NoBomLf $LibPath $raw0
}

# --- load current lib text (now hopefully parseable baseline) ---
$raw = Get-Content -LiteralPath $LibPath -Raw -Encoding UTF8
$raw = $raw.Replace("`r`n","`n")

# --- take a timestamped backup of current state (always) ---
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$bak = $LibPath + ".bak_rescue_" + $ts
WriteUtf8NoBomLf $bak $raw
if(-not (Test-Path -LiteralPath $bak)){ Die ("BACKUP_FAILED: " + $bak) }

# --- locate blocks via brace counting (robust even if internal content is messy) ---
$r1 = Find-BlockRange -Text $raw -Needle "function ConvertTo-OrderedValue"
$r2 = Find-BlockRange -Text $raw -Needle "function To-CanonJson"
if(-not $r1 -or -not $r2){ Die "RESCUE_FAIL: could not locate canon-json functions" }
if($r2.Start -lt $r1.Start){ $tmp=$r1; $r1=$r2; $r2=$tmp }

# --- replacement uses PSCustomObject + Add-Member to preserve sorted insertion without OrderedDictionary ---
$replacement = @'
function ConvertTo-OrderedValue($v){
  if($null -eq $v){ return $null }

  # string is IEnumerable[char]; treat as scalar
  if($v -is [string]){ return $v }

  # IDictionary -> PSCustomObject with sorted keys (no OrderedDictionary object)
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

  # IEnumerable (but not string) -> array
  if($v -is [System.Collections.IEnumerable]){
    $arr = @()
    foreach($x in $v){ $arr += ,(ConvertTo-OrderedValue $x) }
    return $arr
  }

  # PSObject / PSCustomObject -> PSCustomObject with sorted property names
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

$prefix = $raw.Substring(0, [int]$r1.Start)
$suffix = $raw.Substring(([int]$r2.End + 1))
$patched = $prefix.TrimEnd("`n") + "`n`n" + $replacement.TrimEnd("`n") + "`n`n" + $suffix.TrimStart("`n")
WriteUtf8NoBomLf $LibPath $patched

# --- parse gate patched lib ---
[ScriptBlock]::Create((Get-Content -Raw -LiteralPath $LibPath -Encoding UTF8)) | Out-Null
Write-Host "RESCUE_OK: lib restored (if backup existed) + canon-json replaced + lib parses" -ForegroundColor Green
Write-Host ("backup: {0}" -f $bak) -ForegroundColor Cyan
Write-Host ("lib:    {0}" -f $LibPath) -ForegroundColor Cyan

# --- optional diag rerun ---
if($RepoRoot -and (Test-Path -LiteralPath $RepoRoot)){
  $diag = Join-Path $RepoRoot "scripts\_diag_neverlost_name_strictmode_v1.ps1"
  if(Test-Path -LiteralPath $diag){
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $diag -Which make_allowed_signers
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $diag -Which show_identity
  }
}
