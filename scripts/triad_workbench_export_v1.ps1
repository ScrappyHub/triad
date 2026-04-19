param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Ensure-Dir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ throw "ENSURE_DIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ Ensure-Dir $dir }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Sha256HexFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [System.IO.File]::OpenRead($Path)
    try { $hash = $sha.ComputeHash($fs) } finally { $fs.Dispose() }
  } finally {
    $sha.Dispose()
  }
  return ([BitConverter]::ToString($hash)).Replace("-","").ToLowerInvariant()
}

function New-ArtifactObject([string]$BundleRoot,[string]$Name){
  $path = Join-Path $BundleRoot $Name
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){ return $null }
  return [pscustomobject]@{
    name   = $Name
    path   = $path
    sha256 = (Sha256HexFile $path)
    bytes  = [int64](Get-Item -LiteralPath $path).Length
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$FreezeRoot = Join-Path $RepoRoot "proofs\freeze"
$OutDir = Join-Path $RepoRoot "workbench"
$OutPath = Join-Path $OutDir "triad.workbench.export.v1.json"

if(-not (Test-Path -LiteralPath $FreezeRoot -PathType Container)){ Die ("FREEZE_ROOT_NOT_FOUND: " + $FreezeRoot) }
Ensure-Dir $OutDir

$latest = Get-ChildItem -LiteralPath $FreezeRoot -Directory -ErrorAction Stop |
  Where-Object { $_.Name -like "triad_tier0_*" } |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1
if($null -eq $latest){ Die "NO_FREEZE_BUNDLES_FOUND" }

$canonical = Get-ChildItem -LiteralPath $FreezeRoot -Directory -ErrorAction Stop |
  Where-Object { $_.Name -like "triad_tier0_green_*" } |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1
if($null -eq $canonical){ Die "NO_CANONICAL_FREEZE_FOUND" }

$bundleDirs = Get-ChildItem -LiteralPath $FreezeRoot -Directory -ErrorAction Stop |
  Sort-Object LastWriteTimeUtc -Descending

$bundles = @()
foreach($dir in $bundleDirs){
  $artifacts = @()
  foreach($name in @("full_green_transcript.txt","sha256sums.txt","triad.freeze.receipt.json")){
    $a = New-ArtifactObject $dir.FullName $name
    if($null -ne $a){ $artifacts += $a }
  }

  $label = "Proof Bundle"
  if($dir.Name -eq $canonical.Name){
    $label = "Canonical Proof Bundle"
  } elseif($dir.Name -eq $latest.Name){
    $label = "Latest Verified Run"
  }

  $bundles += [pscustomobject]@{
    bundle_id   = $dir.Name
    label       = $label
    path        = $dir.FullName
    pinned      = [bool]($dir.Name -eq $canonical.Name)
    latest      = [bool]($dir.Name -eq $latest.Name)
    created_utc = $dir.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
    artifacts   = @($artifacts)
  }
}

$engineCards = @(
  [pscustomobject]@{
    id = "restore"
    title = "Restore Engine"
    status = "Verified"
    summary = "Prepare, verify, commit, vectors, negatives, and stress lanes."
    proof_lane_count = 10
  },
  [pscustomobject]@{
    id = "archive"
    title = "Archive Engine"
    status = "Verified"
    summary = "Native pack, verify, extract, tamper detection, and traversal refusal."
    proof_lane_count = 6
  },
  [pscustomobject]@{
    id = "transform"
    title = "Transform Engine"
    status = "Verified"
    summary = "Deterministic transforms with manifest proof and mismatch detection."
    proof_lane_count = 5
  }
)

$actions = @(
  [pscustomobject]@{
    id = "run_verified_release"
    label = "Run Verified Full-System Pass"
    kind = "primary"
  },
  [pscustomobject]@{
    id = "open_canonical_bundle"
    label = "Open Canonical Proof Bundle"
    kind = "secondary"
  },
  [pscustomobject]@{
    id = "review_transcript_hashes"
    label = "Review Transcript and Hashes"
    kind = "secondary"
  },
  [pscustomobject]@{
    id = "open_operator_runbook"
    label = "Open Operator Runbook"
    kind = "secondary"
  }
)

$commands = @(
  [pscustomobject]@{
    id = "verified_full_system_run"
    label = "Verified Full-System Run"
    command = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `n  -File .\scripts\_RUN_triad_full_green_v1.ps1 `n  -RepoRoot ."
  },
  [pscustomobject]@{
    id = "external_clone"
    label = "External Verification Clone"
    command = "git clone https://github.com/ScrappyHub/triad.git`ncd triad"
  }
)

$canonicalArtifacts = @()
foreach($name in @("full_green_transcript.txt","sha256sums.txt","triad.freeze.receipt.json")){
  $a = New-ArtifactObject $canonical.FullName $name
  if($null -ne $a){ $canonicalArtifacts += $a }
}

$export = [pscustomobject]@{
  schema = "triad.workbench.export.v1"
  product = [pscustomobject]@{
    name = "TRIAD"
    release_label = "Verified Standalone Release"
    workbench_label = "TRIAD Workbench"
    mode = "local_first"
  }
  summary = [pscustomobject]@{
    release_state = "Verified"
    latest_verified_run_utc = $latest.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
    canonical_bundle_id = $canonical.Name
    bundle_count = (($bundles | Measure-Object).Count)
    engine_count = (($engineCards | Measure-Object).Count)
  }
  canonical_bundle = [pscustomobject]@{
    bundle_id = $canonical.Name
    display_name = "Canonical Proof Bundle"
    path = $canonical.FullName
    created_utc = $canonical.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
    artifacts = @($canonicalArtifacts)
  }
  bundles = @($bundles)
  engines = @($engineCards)
  actions = @($actions)
  commands = @($commands)
}

Write-Utf8NoBomLf $OutPath (($export | ConvertTo-Json -Depth 100 -Compress))
Write-Host ("WORKBENCH_EXPORT_OK: " + $OutPath) -ForegroundColor Green
