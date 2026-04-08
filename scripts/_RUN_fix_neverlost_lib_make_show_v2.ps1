param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Utf8NoBom { New-Object System.Text.UTF8Encoding($false) }
function WriteUtf8NoBomLf([string]$Path,[string]$Content){
  $parent = Split-Path -Parent $Path
  if($parent -and -not (Test-Path -LiteralPath $parent)){ New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $lf = $Content.Replace("`r`n","`n")
  if(-not $lf.EndsWith("`n")){ $lf += "`n" }
  [IO.File]::WriteAllText($Path,$lf,(Utf8NoBom))
}
function ParseGate([string]$Path){ [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Path -Encoding UTF8)) | Out-Null }
if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die ("MISSING_REPO: " + $RepoRoot) }
$ScriptsDir = Join-Path $RepoRoot "scripts"
New-Item -ItemType Directory -Force -Path $ScriptsDir | Out-Null
$LibPath  = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
$MakePath = Join-Path $ScriptsDir "make_allowed_signers_v1.ps1"
$ShowPath = Join-Path $ScriptsDir "show_identity_v1.ps1"
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ScriptsDir ("_neverlost_backup_forcefix_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
foreach($p in @($LibPath,$MakePath,$ShowPath)){ if(Test-Path -LiteralPath $p){ Copy-Item -LiteralPath $p -Destination (Join-Path $BackupDir ((Split-Path -Leaf $p)+".pre_forcefix")) -Force } }
$libLines = @(
  'Set-StrictMode -Version Latest',
  '$ErrorActionPreference = "Stop"',
  '',
  '# StrictMode-safe + self-healing guard:',
  '$nlVar = Get-Variable -Name NL_LIB_LOADED -Scope Global -ErrorAction SilentlyContinue',
  '$needLoad = $true',
  'if(($null -ne $nlVar) -and ($nlVar.Value -eq $true)){ $needLoad = $false }',
  'if(-not (Get-Command NL-WriteAllowedSigners -ErrorAction SilentlyContinue)){ $needLoad = $true }',
  'if(-not (Get-Command NL-GetDefaultPrincipalAndKey -ErrorAction SilentlyContinue)){ $needLoad = $true }',
  'if(-not (Get-Command NL-TrustBundlePath -ErrorAction SilentlyContinue)){ $needLoad = $true }',
  '',
  'if($needLoad){',
  '  $global:NL_LIB_LOADED = $true',
  '',
  '  function NL-Die([string]$m){ throw $m }',
  '  function NL-Utf8NoBom { New-Object System.Text.UTF8Encoding($false) }',
  '',
  '  function NL-WriteUtf8NoBomLf([string]$Path,[string]$Content){',
  '    $parent = Split-Path -Parent $Path',
  '    if($parent -and -not (Test-Path -LiteralPath $parent)){ New-Item -ItemType Directory -Force -Path $parent | Out-Null }',
  '    $lf = $Content.Replace("`r`n","`n")',
  '    if(-not $lf.EndsWith("`n")){ $lf += "`n" }',
  '    [IO.File]::WriteAllText($Path,$lf,(NL-Utf8NoBom))',
  '  }',
  '',
  '  function NL-ReadTextUtf8([string]$Path){',
  '    if(-not (Test-Path -LiteralPath $Path)){ NL-Die ("MISSING_FILE: " + $Path) }',
  '    (Get-Content -LiteralPath $Path -Raw -Encoding UTF8).Replace("`r`n","`n")',
  '  }',
  '',
  '  function NL-ReadJson([string]$Path){',
  '    $raw = NL-ReadTextUtf8 $Path',
  '    try { $raw | ConvertFrom-Json } catch { NL-Die ("JSON_PARSE_FAIL: " + $Path + " :: " + $_.Exception.Message) }',
  '  }',
  '',
  '  function NL-Sha256HexFile([string]$Path){',
  '    if(-not (Test-Path -LiteralPath $Path)){ NL-Die ("MISSING_FILE: " + $Path) }',
  '    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()',
  '  }',
  '',
  '  function NL-ValidatePrincipal([string]$Principal){',
  '    if([string]::IsNullOrWhiteSpace($Principal)){ NL-Die "PRINCIPAL_EMPTY" }',
  '    if($Principal -notmatch "^single-tenant\/[a-z0-9_\-\.]+\/authority\/[a-z0-9_\-\.]+$"){ NL-Die ("PRINCIPAL_INVALID: " + $Principal) }',
  '  }',
  '',
  '  function NL-TrustBundlePath([string]$RepoRoot){ Join-Path $RepoRoot "proofs\trust\trust_bundle.json" }',
  '  function NL-AllowedSignersPath([string]$RepoRoot){ Join-Path $RepoRoot "proofs\trust\allowed_signers" }',
  '',
  '  function NL-HasProperty([object]$Obj, [string]$Name){',
  '    if($null -eq $Obj){ return $false }',
  '    if($null -eq $Obj.PSObject){ return $false }',
  '    $m = @(@($Obj.PSObject.Properties.Match($Name)))',
  '    return ($m.Count -gt 0)',
  '  }',
  '',
  '  function NL-NormalizeKeys([object]$PrincipalRecord){',
  '    if(NL-HasProperty $PrincipalRecord "keys"){ return @(@($PrincipalRecord.keys)) }',
  '    return @($PrincipalRecord)',
  '  }',
  '',
  '  function NL-LoadTrustBundle([string]$RepoRoot){',
  '    $p  = NL-TrustBundlePath $RepoRoot',
  '    $tb = NL-ReadJson $p',
  '    if($null -eq $tb.schema -or [string]$tb.schema -ne "neverlost.trust_bundle.v1"){ NL-Die ("TRUST_BUNDLE_SCHEMA_INVALID: expected neverlost.trust_bundle.v1 :: " + $p) }',
  '    $principals = @(@($tb.principals))',
  '    if($principals.Count -lt 1){ NL-Die ("TRUST_BUNDLE_NO_PRINCIPALS: " + $p) }',
  '    foreach($pr in $principals){',
  '      $pname = [string]$pr.principal',
  '      NL-ValidatePrincipal $pname',
  '      $keys = @(NL-NormalizeKeys $pr)',
  '      if($keys.Count -lt 1){ NL-Die ("TRUST_BUNDLE_PRINCIPAL_NO_KEYS: " + $pname) }',
  '      foreach($k in $keys){',
  '        if([string]::IsNullOrWhiteSpace([string]$k.key_id)){ NL-Die ("KEY_ID_EMPTY: " + $pname) }',
  '        if([string]::IsNullOrWhiteSpace([string]$k.pubkey)){ NL-Die ("PUBKEY_EMPTY: " + $pname + "/" + [string]$k.key_id) }',
  '        $nss = @(@($k.namespaces))',
  '        if($nss.Count -lt 1){ NL-Die ("NAMESPACES_EMPTY: " + $pname + "/" + [string]$k.key_id) }',
  '      }',
  '    }',
  '    $tb',
  '  }',
  '',
  '  function NL-GetDefaultPrincipalAndKey([string]$RepoRoot){',
  '    $tb = NL-LoadTrustBundle $RepoRoot',
  '    $pr = @(@($tb.principals))[0]',
  '    $k  = @(NL-NormalizeKeys $pr)[0]',
  '    [pscustomobject]@{ principal=[string]$pr.principal; key_id=[string]$k.key_id; pubkey=[string]$k.pubkey }',
  '  }',
  '',
  '  function NL-DeriveAllowedSignersText([object]$TrustBundle){',
  '    $lines = New-Object System.Collections.Generic.List[string]',
  '    foreach($pr in @(@($TrustBundle.principals))){',
  '      $principal = [string]$pr.principal',
  '      foreach($k in @(NL-NormalizeKeys $pr)){',
  '        $pub = [string]$k.pubkey',
  '        foreach($ns in @(@($k.namespaces))){',
  '          $ns2 = [string]$ns',
  '          if([string]::IsNullOrWhiteSpace($ns2)){ NL-Die ("NAMESPACE_EMPTY: " + $principal) }',
  '          $lines.Add(("{0} {1} {2}" -f $principal,$ns2,$pub))',
  '        }',
  '      }',
  '    }',
  '    $sorted = @($lines.ToArray() | Sort-Object)',
  '    (($sorted -join "`n") + "`n")',
  '  }',
  '',
  '  function NL-WriteAllowedSigners([string]$RepoRoot){',
  '    $tb  = NL-LoadTrustBundle $RepoRoot',
  '    $out = NL-AllowedSignersPath $RepoRoot',
  '    $txt = NL-DeriveAllowedSignersText $tb',
  '    NL-WriteUtf8NoBomLf $out $txt',
  '    $out',
  '  }',
  '}',
)
$makeLines = @(
  'param([Parameter(Mandatory=$true)][string]$RepoRoot)',
  '$ErrorActionPreference="Stop"',
  'Set-StrictMode -Version Latest',
  '$thisDir = Split-Path -Parent $MyInvocation.MyCommand.Path',
  '$libPath = Join-Path $thisDir "_lib_neverlost_v1.ps1"',
  'if(-not (Test-Path -LiteralPath $libPath)){ throw ("LIB_MISSING: " + $libPath) }',
  'Remove-Variable -Name NL_LIB_LOADED -Scope Global -ErrorAction SilentlyContinue',
  'Remove-Item -Path Function:\NL-* -ErrorAction SilentlyContinue',
  '. $libPath',
  'if(-not (Get-Command NL-WriteAllowedSigners -ErrorAction SilentlyContinue)){ throw ("LIB_DOTSOURCE_FAILED: NL-WriteAllowedSigners :: " + $libPath) }',
  '$out    = NL-WriteAllowedSigners $RepoRoot',
  '$tbPath = NL-TrustBundlePath $RepoRoot',
  '$asPath = NL-AllowedSignersPath $RepoRoot',
  'Write-Host "OK: allowed_signers written deterministically" -ForegroundColor Green',
  'Write-Host ("trust_bundle:    {0}" -f $tbPath) -ForegroundColor Cyan',
  'Write-Host ("allowed_signers: {0}" -f $asPath) -ForegroundColor Cyan',
  'Write-Host ("trust_bundle_sha256:    {0}" -f (NL-Sha256HexFile $tbPath)) -ForegroundColor DarkGray',
  'Write-Host ("allowed_signers_sha256: {0}" -f (NL-Sha256HexFile $asPath)) -ForegroundColor DarkGray',
)
$showLines = @(
  'param([Parameter(Mandatory=$true)][string]$RepoRoot)',
  '$ErrorActionPreference="Stop"',
  'Set-StrictMode -Version Latest',
  '$thisDir = Split-Path -Parent $MyInvocation.MyCommand.Path',
  '$libPath = Join-Path $thisDir "_lib_neverlost_v1.ps1"',
  'if(-not (Test-Path -LiteralPath $libPath)){ throw ("LIB_MISSING: " + $libPath) }',
  'Remove-Variable -Name NL_LIB_LOADED -Scope Global -ErrorAction SilentlyContinue',
  'Remove-Item -Path Function:\NL-* -ErrorAction SilentlyContinue',
  '. $libPath',
  'if(-not (Get-Command NL-GetDefaultPrincipalAndKey -ErrorAction SilentlyContinue)){ throw ("LIB_DOTSOURCE_FAILED: NL-GetDefaultPrincipalAndKey :: " + $libPath) }',
  '$info = NL-GetDefaultPrincipalAndKey $RepoRoot',
  'Write-Host "NeverLost Identity (v1)" -ForegroundColor Green',
  'Write-Host ("principal: {0}" -f $info.principal) -ForegroundColor Cyan',
  'Write-Host ("key_id:    {0}" -f $info.key_id) -ForegroundColor Cyan',
  'Write-Host ("pubkey:    {0}" -f $info.pubkey) -ForegroundColor Cyan',
)
$libText  = ($libLines  -join "`n") + "`n"
$makeText = ($makeLines -join "`n") + "`n"
$showText = ($showLines -join "`n") + "`n"
WriteUtf8NoBomLf $LibPath  $libText
WriteUtf8NoBomLf $MakePath $makeText
WriteUtf8NoBomLf $ShowPath $showText
ParseGate $LibPath
ParseGate $MakePath
ParseGate $ShowPath
Write-Host "OK: forcefix applied" -ForegroundColor Green
Write-Host ("backup_dir: {0}" -f $BackupDir) -ForegroundColor Cyan
Write-Host ("lib_sha256:  {0}" -f (Get-FileHash -Algorithm SHA256 -LiteralPath $LibPath).Hash.ToLowerInvariant()) -ForegroundColor DarkGray
Write-Host "OK: running make/show in-process..." -ForegroundColor Green
& $MakePath -RepoRoot $RepoRoot
& $ShowPath -RepoRoot $RepoRoot
