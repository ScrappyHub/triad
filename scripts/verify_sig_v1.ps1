param(
  [Parameter(Mandatory=$true)][string]$FilePath,
  [Parameter(Mandatory=$true)][string]$SigPath,
  [Parameter(Mandatory=$true)][string]$Namespace,

  [Parameter(Mandatory=$true)][string]$Principal,
  [Parameter(Mandatory=$true)][string]$KeyId,

  [Parameter(Mandatory=$false)][string]$RepoRoot = "",
  [Parameter(Mandatory=$false)][string]$TrustBundlePath = "",
  [Parameter(Mandatory=$false)][string]$AllowedSignersPath = "",
  [Parameter(Mandatory=$false)][string]$ReceiptsPath = ""
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "_lib_neverlost_v1.ps1")

AssertPrincipalFormat $Principal
AssertKeyIdFormat $KeyId
if([string]::IsNullOrWhiteSpace($Namespace)){ Die "NAMESPACE_EMPTY" }

$FilePath = ResolveRealPath $FilePath
$SigPath  = ResolveRealPath $SigPath
if(-not (Test-Path -LiteralPath $FilePath)){ Die ("FILE_MISSING: " + $FilePath) }
if(-not (Test-Path -LiteralPath $SigPath)){ Die ("SIG_MISSING: " + $SigPath) }

if([string]::IsNullOrWhiteSpace($RepoRoot)){
  $RepoRoot = ResolveRealPath (Join-Path $PSScriptRoot "..")
}else{
  $RepoRoot = ResolveRealPath $RepoRoot
}

if([string]::IsNullOrWhiteSpace($TrustBundlePath)){
  $TrustBundlePath = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
}
if([string]::IsNullOrWhiteSpace($AllowedSignersPath)){
  $AllowedSignersPath = Join-Path $RepoRoot "proofs\trust\allowed_signers"
}
if([string]::IsNullOrWhiteSpace($ReceiptsPath)){
  $ReceiptsPath = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"
}

$bundle = LoadTrustBundle $TrustBundlePath
$bundleHash = TrustBundleHash $TrustBundlePath

# enforce: principal exists + key id matches + namespace allowed (reject trust drift)
$rec = $null
foreach($p in $bundle.principals){
  if([string]$p.principal -eq $Principal -and [string]$p.key_id -eq $KeyId){
    $rec = $p; break
  }
}
if($null -eq $rec){ Die ("TRUST_NOT_FOUND: principal={0} key_id={1}" -f $Principal,$KeyId) }

$nsOk = $false
foreach($n in $rec.namespaces){
  if([string]$n -eq $Namespace){ $nsOk = $true; break }
}
if(-not $nsOk){ Die ("NAMESPACE_NOT_ALLOWED: principal={0} ns={1}" -f $Principal,$Namespace) }

# ensure allowed_signers exists (materialize is separate action)
if(-not (Test-Path -LiteralPath $AllowedSignersPath)){ Die ("ALLOWED_SIGNERS_MISSING: " + $AllowedSignersPath) }

# compute target hashes (receipt invariants)
$fileHash = Sha256HexPath $FilePath
$sigHash  = Sha256HexPath $SigPath
$asHash   = Sha256HexPath $AllowedSignersPath

# cryptographic verify (ssh-keygen -Y verify) with namespace enforcement
$res = SshYVerifyFile $AllowedSignersPath $Principal $Namespace $SigPath $FilePath

$ok = [bool]$res.ok
$reason = ""
if(-not $ok){
  $reason = [string]$res.detail
}

$rcpt = [ordered]@{
  schema = "neverlost.receipt.v1"
  action = "verify_sig"
  repo_root = $RepoRoot
  utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  principal = $Principal
  key_id = $KeyId
  namespace = $Namespace
  file_path = (RelPathUnix $RepoRoot $FilePath)
  file_sha256 = $fileHash
  sig_path = (RelPathUnix $RepoRoot $SigPath)
  sig_sha256 = $sigHash
  trust_bundle_path = (RelPathUnix $RepoRoot $TrustBundlePath)
  trust_bundle_sha256 = $bundleHash
  allowed_signers_path = (RelPathUnix $RepoRoot $AllowedSignersPath)
  allowed_signers_sha256 = $asHash
  ok = $ok
  fail_reason = $reason
}

Write-NeverLostReceipt $ReceiptsPath $rcpt

if($ok){
  Write-Host "VERIFY_SIG OK" -ForegroundColor Green
}else{
  Write-Host "VERIFY_SIG FAIL" -ForegroundColor Red
  Write-Host $reason -ForegroundColor Yellow
  exit 2
}
