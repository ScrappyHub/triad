param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Sha([string]$p){
  if(-not (Test-Path -LiteralPath $p)){ return "" }
  (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant()
}
function Size([string]$p){
  if(-not (Test-Path -LiteralPath $p)){ return -1 }
  (Get-Item -LiteralPath $p).Length
}
function Head([string]$p,[int]$n){
  if(-not (Test-Path -LiteralPath $p)){ return }
  Write-Host ""
  Write-Host ("----- HEAD {0} lines: {1}" -f $n,$p) -ForegroundColor Yellow
  Get-Content -LiteralPath $p -Encoding UTF8 -TotalCount $n | ForEach-Object { $_ }
}

function MaxJsonNesting([string]$json){
  $depth = 0
  $max = 0
  foreach($ch in $json.ToCharArray()){
    if($ch -eq '{' -or $ch -eq '['){ $depth++; if($depth -gt $max){ $max = $depth } }
    elseif($ch -eq '}' -or $ch -eq ']'){ if($depth -gt 0){ $depth-- } }
  }
  return $max
}

if(-not (Test-Path -LiteralPath $RepoRoot)){ Die ("MISSING_REPO: " + $RepoRoot) }

$ScriptsDir = Join-Path $RepoRoot "scripts"
$LibPath    = Join-Path $ScriptsDir "_lib_neverlost_v1.ps1"
$MakePath   = Join-Path $ScriptsDir "make_allowed_signers_v1.ps1"
$ShowPath   = Join-Path $ScriptsDir "show_identity_v1.ps1"
$TbPath     = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"

Write-Host "=== NEVERLOST DIAG v1 ===" -ForegroundColor Green
Write-Host ("repo_root:  {0}" -f $RepoRoot) -ForegroundColor Cyan
Write-Host ("pwsh:       {0}" -f $PSVersionTable.PSVersion.ToString()) -ForegroundColor Cyan
Write-Host ("edition:    {0}" -f $PSVersionTable.PSEdition) -ForegroundColor Cyan
Write-Host ("exe:        {0}" -f (Get-Process -Id $PID).Path) -ForegroundColor Cyan

Write-Host ""
Write-Host "=== FILES ===" -ForegroundColor Green
foreach($p in @($LibPath,$MakePath,$ShowPath,$TbPath)){
  $exists = Test-Path -LiteralPath $p
  Write-Host ("{0}" -f $p) -ForegroundColor Cyan
  Write-Host ("  exists: {0}" -f $exists) -ForegroundColor DarkGray
  if($exists){
    Write-Host ("  bytes:  {0}" -f (Size $p)) -ForegroundColor DarkGray
    Write-Host ("  sha256: {0}" -f (Sha $p)) -ForegroundColor DarkGray
  }
}

# show a little content so we can SEE recursion triggers
Head $LibPath  80
Head $MakePath 80
Head $ShowPath 80

# scan for common recursion triggers
if(Test-Path -LiteralPath $LibPath){
  Write-Host ""
  Write-Host "=== SCAN lib for dot-sourcing / self-reference ===" -ForegroundColor Green
  $hits = Select-String -LiteralPath $LibPath -Pattern '\.\s*\(Join-Path\s+\$PSScriptRoot\s+"?_lib_neverlost_v1\.ps1"?\)' -AllMatches -ErrorAction SilentlyContinue
  if($hits){ $hits | ForEach-Object { Write-Host ("HIT: {0}:{1} {2}" -f $_.Path,$_.LineNumber,$_.Line) -ForegroundColor Red } }
  else { Write-Host "OK: no obvious self-dot-source line found" -ForegroundColor DarkGray }

  $hits2 = Select-String -LiteralPath $LibPath -Pattern 'function\s+NL\-' -AllMatches -ErrorAction SilentlyContinue
  Write-Host ("functions_found: {0}" -f (@($hits2).Count)) -ForegroundColor DarkGray
}

# trust bundle nesting depth
if(Test-Path -LiteralPath $TbPath){
  $raw = Get-Content -LiteralPath $TbPath -Raw -Encoding UTF8
  $max = MaxJsonNesting $raw
  Write-Host ""
  Write-Host "=== TRUST BUNDLE ===" -ForegroundColor Green
  Write-Host ("tb_bytes:      {0}" -f ($raw.Length)) -ForegroundColor DarkGray
  Write-Host ("max_nesting:   {0}" -f $max) -ForegroundColor DarkGray

  Write-Host ""
  Write-Host "=== TRY ConvertFrom-Json ===" -ForegroundColor Green
  try {
    $obj = $raw | ConvertFrom-Json -Depth 100
    Write-Host "OK: ConvertFrom-Json succeeded" -ForegroundColor Green
    Write-Host ("principals_type: {0}" -f ($obj.principals.GetType().FullName)) -ForegroundColor DarkGray
  } catch {
    Write-Host ("FAIL: ConvertFrom-Json :: {0}" -f $_.Exception.Message) -ForegroundColor Red
  }
} else {
  Write-Host ""
  Write-Host "NOTE: trust_bundle.json missing, so make/show will be skipped." -ForegroundColor Yellow
}

# finally, try to run the scripts and capture the first error message
if(Test-Path -LiteralPath $TbPath){
  Write-Host ""
  Write-Host "=== EXECUTE make_allowed_signers_v1.ps1 ===" -ForegroundColor Green
  try {
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $MakePath -RepoRoot $RepoRoot
    Write-Host "OK: make_allowed_signers completed" -ForegroundColor Green
  } catch {
    Write-Host ("FAIL: make_allowed_signers :: {0}" -f $_.Exception.Message) -ForegroundColor Red
  }

  Write-Host ""
  Write-Host "=== EXECUTE show_identity_v1.ps1 ===" -ForegroundColor Green
  try {
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ShowPath -RepoRoot $RepoRoot
    Write-Host "OK: show_identity completed" -ForegroundColor Green
  } catch {
    Write-Host ("FAIL: show_identity :: {0}" -f $_.Exception.Message) -ForegroundColor Red
  }
}
