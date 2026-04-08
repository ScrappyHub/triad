$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$RepoRoot = "C:\dev\triad"
$Lib      = Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1"
$Patcher  = Join-Path $RepoRoot "scripts\_patch_neverlost_canonjson_fix_v2.ps1"
$Diag     = Join-Path $RepoRoot "scripts\_diag_neverlost_name_strictmode_v1.ps1"

$patcherText = @'
param([Parameter(Mandatory=$true)][string]$LibPath)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
if(-not (Test-Path -LiteralPath $LibPath)){ Die ("MISSING: " + $LibPath) }
$raw = Get-Content -LiteralPath $LibPath -Raw -Encoding UTF8
$raw = $raw.Replace("`r`n","`n")
$pattern = '(?s)function\s+ConvertTo-OrderedValue\(\$v\)\s*\{.*?\}\s*\n\s*function\s+To-CanonJson\(\$obj,\[int\]\$Depth=32\)\s*\{.*?\}\s*'
if($raw -notmatch $pattern){ Die "PATCH_FAIL: could not find canon-json block (content drift)" }
$replacement = @'
function ConvertTo-OrderedValue($v){
  if($null -eq $v){ return $null }
  if($v -is [string]){ return $v }
  if($v -is [System.Collections.IDictionary]){
    $keys = @($v.Keys) | ForEach-Object { [string]$_ } | Sort-Object
    $o = [ordered]@{}
    foreach($k in $keys){ $o[$k] = ConvertTo-OrderedValue $v[$k] }
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
      if(($mi -is [System.Management.Automation.PSMemberInfo]) -or ($mi -is [System.Management.Automation.PSPropertyInfo])){
        if($mi.MemberType -in @("NoteProperty","Property")){ $names += [string]$mi.Name }
      }
    }
    $names = @($names) | Sort-Object
    if($names.Count -gt 0){
      $o = [ordered]@{}
      foreach($n in $names){ $o[$n] = ConvertTo-OrderedValue ($v.PSObject.Properties[$n].Value) }
      return $o
    }
  }
  return $v
}
function To-CanonJson($obj,[int]$Depth=32){
  $ordered = ConvertTo-OrderedValue $obj
  return ($ordered | ConvertTo-Json -Depth $Depth -Compress)
}
