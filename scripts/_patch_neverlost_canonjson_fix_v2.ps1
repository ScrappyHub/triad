param([Parameter(Mandatory=$true)][string]$LibPath)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
if(-not (Test-Path -LiteralPath $LibPath)){ Die ("MISSING: " + $LibPath) }

$raw = Get-Content -LiteralPath $LibPath -Raw -Encoding UTF8
$raw = $raw.Replace("`r`n","`n")

# Replace ConvertTo-OrderedValue + To-CanonJson as a single block
$pattern = '(?s)function\s+ConvertTo-OrderedValue\(\$v\)\s*\{.*?\}\s*\n\s*function\s+To-CanonJson\(\$obj,\[int\]\$Depth=32\)\s*\{.*?\}\s*'
if($raw -notmatch $pattern){ Die "PATCH_FAIL: could not find canon-json block (content drift)" }

$replacement = @'
function ConvertTo-OrderedValue($v){
  if($null -eq $v){ return $null }

  # Treat strings as scalars early (string is IEnumerable[char])
  if($v -is [string]){ return $v }

  # IDictionary (hashtable / ordered)
  if($v -is [System.Collections.IDictionary]){
    $keys = @($v.Keys) | ForEach-Object { [string]$_ } | Sort-Object
    $o = [ordered]@{}
    foreach($k in $keys){
      $o[$k] = ConvertTo-OrderedValue $v[$k]
    }
    return $o
  }

  # Arrays / lists (IEnumerable but not string)
  if($v -is [System.Collections.IEnumerable]){
    $arr = @()
    foreach($x in $v){
      $arr += ,(ConvertTo-OrderedValue $x)
    }
    return $arr
  }

  # PSObject / PSCustomObject -> enumerate properties safely
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
      $o = [ordered]@{}
      foreach($n in $names){
        $o[$n] = ConvertTo-OrderedValue ($v.PSObject.Properties[$n].Value)
      }
      return $o
    }
  }

  return $v
}

function To-CanonJson($obj,[int]$Depth=32){
  $ordered = ConvertTo-OrderedValue $obj
  return ($ordered | ConvertTo-Json -Depth $Depth -Compress)
}
'@

$raw = [System.Text.RegularExpressions.Regex]::Replace($raw, $pattern, $replacement, 1)
if(-not $raw.EndsWith("`n")){ $raw += "`n" }
[IO.File]::WriteAllText($LibPath, $raw, (New-Object System.Text.UTF8Encoding($false)))

# Parse gate patched lib
[ScriptBlock]::Create((Get-Content -Raw -LiteralPath $LibPath -Encoding UTF8)) | Out-Null
Write-Host "PATCH_OK: canon-json block replaced (v2)" -ForegroundColor Green
Write-Host ("lib: {0}" -f $LibPath) -ForegroundColor Cyan
