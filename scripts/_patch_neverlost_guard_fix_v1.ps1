param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
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

$LibPath  = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
$MakePath = Join-Path $ScriptsDir "make_allowed_signers_v1.ps1"
$ShowPath = Join-Path $ScriptsDir "show_identity_v1.ps1"

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ScriptsDir ("_neverlost_backup_guardfix_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

foreach($p in @($LibPath,$MakePath,$ShowPath)){
  if(Test-Path -LiteralPath $p){
    Copy-Item -LiteralPath $p -Destination (Join-Path $BackupDir ((Split-Path -Leaf $p) + ".pre_guardfix")) -Force
  }
}

if(-not (Test-Path -LiteralPath $LibPath)){ Die ("LIB_MISSING: " + $LibPath) }

# Read + normalize
$raw = (Get-Content -LiteralPath $LibPath -Raw -Encoding UTF8).Replace("`r`n","`n")

# Replace ONLY the unsafe guard (StrictMode breaks on reading unset $global:NL_LIB_LOADED)
$needle = 'if($global:NL_LIB_LOADED -ne $true){' + "`n" + '  $global:NL_LIB_LOADED = $true'
if($raw -notlike "*$needle*"){
  Die "GUARD_PATTERN_NOT_FOUND: lib does not contain expected unsafe guard block"
}

$replacement = @(
'# StrictMode-safe guard: never read an unset variable directly',
'$nlVar = Get-Variable -Name NL_LIB_LOADED -Scope Global -ErrorAction SilentlyContinue',
'if(($null -eq $nlVar) -or ($nlVar.Value -ne $true)){',
'  $global:NL_LIB_LOADED = $true'
) -join "`n"

$patched = $raw.Replace($needle, $replacement)

# Write back deterministically + parse gate
WriteUtf8NoBomLf $LibPath ($patched + "`n")
ParseGate $LibPath

Write-Host "OK: NL lib guard patched (StrictMode-safe)" -ForegroundColor Green
Write-Host ("backup_dir: {0}" -f $BackupDir) -ForegroundColor Cyan
Write-Host ("lib_bytes:  {0}" -f ((Get-Item -LiteralPath $LibPath).Length)) -ForegroundColor Cyan
Write-Host ("lib_sha256: {0}" -f (Get-FileHash -Algorithm SHA256 -LiteralPath $LibPath).Hash.ToLowerInvariant()) -ForegroundColor DarkGray

# Now run in-process (no nested shells) to prove it doesn't explode
if(-not (Test-Path -LiteralPath $MakePath)){ Die ("MAKE_MISSING: " + $MakePath) }
if(-not (Test-Path -LiteralPath $ShowPath)){ Die ("SHOW_MISSING: " + $ShowPath) }

ParseGate $MakePath
ParseGate $ShowPath

Write-Host "OK: executing make/show in-process (dot-source should be safe now)..." -ForegroundColor Green
& $MakePath -RepoRoot $RepoRoot
& $ShowPath -RepoRoot $RepoRoot
