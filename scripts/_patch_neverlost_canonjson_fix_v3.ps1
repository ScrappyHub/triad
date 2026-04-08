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

  # Treat strings as scalars early (string is IEnumerable[char])
  if($v -is [string]){ return $v }

  # IDictionary -> return *Hashtable* (NOT OrderedDictionary) for ConvertTo-Json compatibility
  if($v -is [System.Collections.IDictionary]){
    $keys = @($v.Keys) | ForEach-Object { [string]$_ } | Sort-Object
    $h = @{}
    foreach($k in $keys){
      $h[$k] = ConvertTo-OrderedValue $v[$k]
    }
    return $h
  }

  # Arrays / lists (IEnumerable but not string)
  if($v -is [System.Collections.IEnumerable]){
    $arr = @()
    foreach($x in $v){
      $arr += ,(ConvertTo-OrderedValue $x)
    }
    return $arr
  }

  # PSObject / PSCustomObject -> hashtable with sorted names
  if($v -is [psobject]){
    $names = @()
    foreach($mi in $v.PSObject.Properties){
      if($mi -is [System.Management.Automation.PSMemberInfo]){
        if($mi.MemberType -in @("NoteProperty","Property")){
          $names += [string]$mi.Name
        }
      }
    }
    $names = @($names) | Sort-Object

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
'@

$raw = [System.Text.RegularExpressions.Regex]::Replace($raw, $pattern, $replacement, 1)
if(-not $raw.EndsWith("`n")){ $raw += "`n" }
[IO.File]::WriteAllText($LibPath, $raw, (New-Object System.Text.UTF8Encoding($false)))
[ScriptBlock]::Create((Get-Content -Raw -LiteralPath $LibPath -Encoding UTF8)) | Out-Null
Write-Host "PATCH_OK: canon-json block replaced (v3-no-ordereddict)" -ForegroundColor Green
Write-Host ("lib: {0}" -f $LibPath) -ForegroundColor Cyan
