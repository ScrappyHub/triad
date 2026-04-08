param([Parameter(Mandatory=$true)][string]$LibPath)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

if(-not (Test-Path -LiteralPath $LibPath)){ Die ("MISSING_LIB: " + $LibPath) }

$raw = Get-Content -LiteralPath $LibPath -Raw -Encoding UTF8
$raw = $raw.Replace("`r`n","`n")

# Replace ConvertTo-OrderedValue + To-CanonJson as a single block (even if currently broken)
$pattern = '(?s)function\s+ConvertTo-OrderedValue\(\$v\)\s*\{.*?\}\s*\n\s*function\s+To-CanonJson\(\$obj,\[int\]\$Depth=32\)\s*\{.*?\}\s*'
if($raw -notmatch $pattern){
  Die "RESCUE_FAIL: could not find canon-json block to replace (content drift)"
}

$replacement = @'
function ConvertTo-OrderedValue($v){
  if($null -eq $v){ return $null }

  # string is IEnumerable[char]; treat as scalar
  if($v -is [string]){ return $v }

  # IDictionary -> hashtable (NOT [ordered]) for ConvertTo-Json compatibility
  if($v -is [System.Collections.IDictionary]){
    $keys = @()
    foreach($k in $v.Keys){ $keys += [string]$k }
    $keys = @($keys | Sort-Object)

    $h = @{}
    foreach($k in $keys){
      $h[$k] = ConvertTo-OrderedValue $v[$k]
    }
    return $h
  }

  # IEnumerable (but not string) -> array
  if($v -is [System.Collections.IEnumerable]){
    $arr = @()
    foreach($x in $v){
      $arr += ,(ConvertTo-OrderedValue $x)
    }
    return $arr
  }

  # PSObject/PSCustomObject -> hashtable with sorted property names
  if($v -is [psobject]){
    $names = @()
    foreach($mi in $v.PSObject.Properties){
      if($mi -is [System.Management.Automation.PSMemberInfo]){
        if($mi.MemberType -in @("NoteProperty","Property")){
          $names += [string]$mi.Name
        }
      }
    }
    $names = @($names | Sort-Object)

    if($names.Count -gt 0){
      $h = @{}
      foreach($n in $names){
        $h[$n] = ConvertTo-OrderedValue ($v.PSObject.Properties[$n].Value)
      }
      return $h
    }
  }

  return $v
}

function To-CanonJson($obj,[int]$Depth=32){
  $canon = ConvertTo-OrderedValue $obj
  return ($canon | ConvertTo-Json -Depth $Depth -Compress)
}
