param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function Utf8NoBom { New-Object System.Text.UTF8Encoding($false) }
function WriteUtf8NoBomLf([string]$Path,[string]$Content){
  $parent = Split-Path -Parent $Path
  if($parent -and -not (Test-Path -LiteralPath $parent)){
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $lf = $Content.Replace("`r`n","`n")
  if(-not $lf.EndsWith("`n")){ $lf += "`n" }
  [IO.File]::WriteAllText($Path,$lf,(Utf8NoBom))
}
function ParseGate([string]$Path){
  [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Path -Encoding UTF8)) | Out-Null
}

if(-not (Test-Path -LiteralPath $RepoRoot)){ Die ("MISSING_REPO: " + $RepoRoot) }

$ScriptsDir = Join-Path $RepoRoot "scripts"
New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null

$Seed = Join-Path $ScriptsDir "_neverlost_seed_bundle_v1.ps1"

# ----------------------------
# SEED SCRIPT CONTENT (verbatim)
# ----------------------------
$seedSrc = @'
param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function Utf8NoBom { New-Object System.Text.UTF8Encoding($false) }
function WriteUtf8NoBomLf([string]$Path,[string]$Content){
  $parent = Split-Path -Parent $Path
  if($parent -and -not (Test-Path -LiteralPath $parent)){
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $lf = $Content.Replace("`r`n","`n")
  if(-not $lf.EndsWith("`n")){ $lf += "`n" }
  [IO.File]::WriteAllText($Path,$lf,(Utf8NoBom))
}
function ParseGate([string]$Path){
  [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Path -Encoding UTF8)) | Out-Null
}

if(-not (Test-Path -LiteralPath $RepoRoot)){ Die ("MISSING_REPO: " + $RepoRoot) }

$ScriptsDir = Join-Path $RepoRoot "scripts"
New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ScriptsDir ("_neverlost_backup_seed_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

$targets = @(
  "_lib_neverlost_v1.ps1",
  "make_allowed_signers_v1.ps1",
  "show_identity_v1.ps1",
  "verify_sig_v1.ps1",
  "sign_file_v1.ps1"
)
foreach($t in $targets){
  $p = Join-Path $ScriptsDir $t
  if(Test-Path -LiteralPath $p){
    Copy-Item -LiteralPath $p -Destination (Join-Path $BackupDir ($t + ".old_or_corrupt")) -Force
  }
}

# 1) _lib_neverlost_v1.ps1
$lib = @'
# NeverLost v1 — canonical identity + trust + receipts helpers
# Deterministic: UTF-8 no BOM, LF, no hidden machine defaults.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function NL-Die([string]$m){ throw $m }
function NL-Utf8NoBom { New-Object System.Text.UTF8Encoding($false) }

function NL-WriteUtf8NoBomLf([string]$Path,[string]$Content){
  $parent = Split-Path -Parent $Path
  if($parent -and -not (Test-Path -LiteralPath $parent)){
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $lf = $Content.Replace("`r`n","`n")
  if(-not $lf.EndsWith("`n")){ $lf += "`n" }
  [IO.File]::WriteAllText($Path,$lf,(NL-Utf8NoBom))
}

function NL-ReadTextUtf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path)){ NL-Die ("MISSING_FILE: " + $Path) }
  $t = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  return $t.Replace("`r`n","`n")
}

function NL-Sha256HexFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path)){ NL-Die ("MISSING_FILE: " + $Path) }
  $h = Get-FileHash -Algorithm SHA256 -LiteralPath $Path
  return ($h.Hash.ToLowerInvariant())
}

function NL-ReadJson([string]$Path){
  $raw = NL-ReadTextUtf8 $Path
  try { return ($raw | ConvertFrom-Json -Depth 100) }
  catch { NL-Die ("JSON_PARSE_FAIL: " + $Path + " :: " + $_.Exception.Message) }
}

function NL-ValidatePrincipal([string]$Principal){
  if([string]::IsNullOrWhiteSpace($Principal)){ NL-Die "PRINCIPAL_EMPTY" }
  if($Principal -notmatch '^single-tenant\/[a-z0-9_\-\.]+\/authority\/[a-z0-9_\-\.]+$'){
    NL-Die ("PRINCIPAL_INVALID: " + $Principal)
  }
}

function NL-TrustBundlePath([string]$RepoRoot){ Join-Path $RepoRoot "proofs\trust\trust_bundle.json" }
function NL-AllowedSignersPath([string]$RepoRoot){ Join-Path $RepoRoot "proofs\trust\allowed_signers" }
function NL-ReceiptsPath([string]$RepoRoot){ Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson" }

function NL-LoadTrustBundle([string]$RepoRoot){
  $p = NL-TrustBundlePath $RepoRoot
  $tb = NL-ReadJson $p
  if($null -eq $tb.schema -or $tb.schema -ne "neverlost.trust_bundle.v1"){
    NL-Die ("TRUST_BUNDLE_SCHEMA_INVALID: expected neverlost.trust_bundle.v1 :: " + $p)
  }
  if($null -eq $tb.principals -or $tb.principals.Count -lt 1){
    NL-Die ("TRUST_BUNDLE_NO_PRINCIPALS: " + $p)
  }
  foreach($pr in $tb.principals){
    NL-ValidatePrincipal ([string]$pr.principal)
    if($null -eq $pr.keys -or $pr.keys.Count -lt 1){
      NL-Die ("TRUST_BUNDLE_PRINCIPAL_NO_KEYS: " + $pr.principal)
    }
    foreach($k in $pr.keys){
      if([string]::IsNullOrWhiteSpace([string]$k.key_id)){ NL-Die ("KEY_ID_EMPTY: " + $pr.principal) }
      if([string]::IsNullOrWhiteSpace([string]$k.pubkey)){ NL-Die ("PUBKEY_EMPTY: " + $pr.principal + "/" + $k.key_id) }
      if($null -eq $k.namespaces -or $k.namespaces.Count -lt 1){
        NL-Die ("NAMESPACES_EMPTY: " + $pr.principal + "/" + $k.key_id)
      }
    }
  }
  return $tb
}

function NL-ConvertToOrderedValue($v){
  if($null -eq $v){ return $null }
  if($v -is [string]){ return $v }
  if($v -is [System.Collections.IDictionary]){
    $keys = @()
    foreach($k in $v.Keys){ $keys += [string]$k }
    $keys = @($keys | Sort-Object)
    $o = [pscustomobject]@{}
    foreach($k in $keys){
      $o | Add-Member -MemberType NoteProperty -Name $k -Value (NL-ConvertToOrderedValue $v[$k])
    }
    return $o
  }
  if($v -is [System.Collections.IEnumerable]){
    $arr = @()
    foreach($x in $v){ $arr += ,(NL-ConvertToOrderedValue $x) }
    return $arr
  }
  if($v -is [psobject]){
    $names = @()
    foreach($mi in $v.PSObject.Properties){
      if($mi.MemberType -in @("NoteProperty","Property")){ $names += [string]$mi.Name }
    }
    $names = @($names | Sort-Object)
    if($names.Count -gt 0){
      $o = [pscustomobject]@{}
      foreach($n in $names){
        $o | Add-Member -MemberType NoteProperty -Name $n -Value (NL-ConvertToOrderedValue ($v.PSObject.Properties[$n].Value))
      }
      return $o
    }
  }
  return $v
}

function NL-ToCanonJson($obj,[int]$Depth=64){
  $canon = NL-ConvertToOrderedValue $obj
  return ($canon | ConvertTo-Json -Depth $Depth -Compress)
}

function NL-DeriveAllowedSignersText([object]$TrustBundle){
  $lines = New-Object System.Collections.Generic.List[string]
  foreach($pr in $TrustBundle.principals){
    $principal = [string]$pr.principal
    foreach($k in $pr.keys){
      $pub = [string]$k.pubkey
      foreach($ns in $k.namespaces){
        $ns2 = [string]$ns
        if([string]::IsNullOrWhiteSpace($ns2)){ NL-Die ("NAMESPACE_EMPTY: " + $principal) }
        $lines.Add(("{0} {1} {2}" -f $principal,$ns2,$pub))
      }
    }
  }
  $sorted = @($lines.ToArray() | Sort-Object)
  return (($sorted -join "`n") + "`n")
}

function NL-WriteAllowedSigners([string]$RepoRoot){
  $tb = NL-LoadTrustBundle $RepoRoot
  $out = NL-AllowedSignersPath $RepoRoot
  $txt = NL-DeriveAllowedSignersText $tb
  NL-WriteUtf8NoBomLf $out $txt
  return $out
}

function NL-AppendReceipt([string]$RepoRoot,[object]$Receipt){
  $path = NL-ReceiptsPath $RepoRoot
  $parent = Split-Path -Parent $path
  if(-not (Test-Path -LiteralPath $parent)){ New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $line = NL-ToCanonJson $Receipt
  [IO.File]::AppendAllText($path, ($line + "`n"), (NL-Utf8NoBom))
  return $path
}

function NL-GetDefaultPrincipalAndKey([string]$RepoRoot){
  $tb = NL-LoadTrustBundle $RepoRoot
  $pr = $tb.principals[0]
  $k  = $pr.keys[0]
  return [pscustomobject]@{
    principal = [string]$pr.principal
    key_id    = [string]$k.key_id
    pubkey    = [string]$k.pubkey
  }
}

function NL-FindSinglePrivateKey([string]$RepoRoot){
  $keysDir = Join-Path $RepoRoot "proofs\keys"
  if(-not (Test-Path -LiteralPath $keysDir)){ NL-Die ("MISSING_KEYS_DIR: " + $keysDir) }
  $cands = Get-ChildItem -LiteralPath $keysDir -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -notlike "*.pub" -and $_.Name -notlike "*.txt" -and $_.Name -notlike "*.json"
  }
  if(-not $cands -or $cands.Count -lt 1){ NL-Die ("NO_PRIVATE_KEYS_FOUND: " + $keysDir) }
  if($cands.Count -ne 1){ NL-Die ("MULTIPLE_PRIVATE_KEYS_FOUND: " + (($cands | ForEach-Object Name | Sort-Object) -join ", ")) }
  return $cands[0].FullName
}

function NL-RequireSshKeygen(){
  $ok = $true
  try { & ssh-keygen -V | Out-Null } catch { $ok = $false }
  if(-not $ok){ NL-Die "SSH_KEYGEN_NOT_FOUND: ssh-keygen not available on PATH" }
}
