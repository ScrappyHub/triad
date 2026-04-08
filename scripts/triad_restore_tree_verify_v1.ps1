param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$PlanPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Sha256HexBytes([byte[]]$Bytes){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $h = $sha.ComputeHash($Bytes)
    ($h | ForEach-Object { $_.ToString("x2") }) -join ""
  } finally { $sha.Dispose() }
}

function Sha256HexFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function HexToBytes([string]$Hex){
  if([string]::IsNullOrWhiteSpace($Hex)){ Die "HEX_EMPTY" }
  if(($Hex.Length % 2) -ne 0){ Die ("HEX_ODD_LEN: " + $Hex.Length) }
  $len = $Hex.Length / 2
  $b = New-Object byte[] $len
  for($i=0; $i -lt $len; $i++){
    $b[$i] = [Convert]::ToByte($Hex.Substring($i*2,2),16)
  }
  $b
}

function MerkleRootHex([string[]]$HexHashesInOrder){
  $arr = @(@($HexHashesInOrder))
  if($arr.Count -lt 1){ Die "MERKLE_EMPTY" }

  $level = New-Object System.Collections.Generic.List[byte[]]
  foreach($hx in $arr){ [void]$level.Add((HexToBytes $hx)) }

  while($level.Count -gt 1){
    $next = New-Object System.Collections.Generic.List[byte[]]
    for($i=0; $i -lt $level.Count; $i += 2){
      $a = $level[$i]
      $b = $null
      if(($i+1) -lt $level.Count){ $b = $level[$i+1] } else { $b = $level[$i] }
      $cat = New-Object byte[] ($a.Length + $b.Length)
      [Array]::Copy($a,0,$cat,0,$a.Length)
      [Array]::Copy($b,0,$cat,$a.Length,$b.Length)
      $sha = [System.Security.Cryptography.SHA256]::Create()
      try {
        $h = $sha.ComputeHash($cat)
        [void]$next.Add($h)
      } finally { $sha.Dispose() }
    }
    $level = $next
  }
  ($level[0] | ForEach-Object { $_.ToString("x2") }) -join ""
}

function ReadJson([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  $raw = (Get-Content -Raw -LiteralPath $Path -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
  try { $raw | ConvertFrom-Json } catch { Die ("JSON_PARSE_FAIL: " + $Path + " :: " + $_.Exception.Message) }
}

function EntryHashV1([string]$Type,[string]$Rel,[int64]$Len,[string]$Sha){
  $s = ("triad.tree.entry.v1|{0}|{1}|{2}|{3}" -f $Type,$Rel,$Len,$Sha)
  Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($s))
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die ("MISSING_REPO: " + $RepoRoot) }
if(-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)){ Die ("MISSING_PLAN: " + $PlanPath) }

$plan = ReadJson $PlanPath
if([string]$plan.schema -ne "triad.restore_tree_plan.v1"){ Die ("PLAN_SCHEMA_UNEXPECTED: " + [string]$plan.schema) }

$SnapshotDir  = [string]$plan.snapshot_dir
$ManifestPath = [string]$plan.manifest_path
$TmpDir       = [string]$plan.tmp_dir

if(-not (Test-Path -LiteralPath $SnapshotDir -PathType Container)){ Die ("MISSING_SNAPSHOT_DIR: " + $SnapshotDir) }
if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){ Die ("MISSING_MANIFEST: " + $ManifestPath) }
if(-not (Test-Path -LiteralPath $TmpDir -PathType Container)){ Die ("MISSING_TMP_DIR: " + $TmpDir) }

$man = ReadJson $ManifestPath
if([string]$man.schema -ne "triad.snapshot_tree.v1"){ Die ("MANIFEST_SCHEMA_UNEXPECTED: " + [string]$man.schema) }

$expectedSemantic = [string]$man.roots.semantic_root
$expectedBlock    = [string]$man.roots.block_root
$expectedFiles    = [int]$man.source.files
$expectedDirs     = [int]$man.source.dirs
$expectedBytes    = [int64]$man.source.total_bytes

$entries = @(@($man.entries))
if($entries.Count -lt 1){ Die "MANIFEST_NO_ENTRIES" }

# 1) verify blocks hash to their names; collect UNIQUE blocks for block_root
$blkSet = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
$blkList = New-Object System.Collections.Generic.List[string]

foreach($e in $entries){
  if([string]$e.type -eq "file"){
    foreach($b in @(@($e.blocks))){
      $sha = [string]$b.sha256
      $rel = [string]$b.path
      if($sha -notmatch "^[0-9a-f]{64}$"){ Die ("BLOCK_SHA_SHAPE_INVALID: " + $sha) }
      if($rel -notmatch "^blocks\/[0-9a-f]{64}\.blk$"){ Die ("BLOCK_PATH_SHAPE_INVALID: " + $rel) }
      $blkPath = Join-Path $SnapshotDir ($rel -replace "/","\")
      if(-not (Test-Path -LiteralPath $blkPath -PathType Leaf)){ Die ("MISSING_BLOCK_FILE: " + $blkPath) }
      $h = Sha256HexFile $blkPath
      if($h -ne $sha){ Die ("BLOCK_HASH_MISMATCH: expected=" + $sha + " got=" + $h + " file=" + $blkPath) }
      if($blkSet.Add($sha)){
        [void]$blkList.Add($sha)
      }
    }
  }
}

$blkSorted = @($blkList.ToArray() | Sort-Object)
if($blkSorted.Count -lt 1){ Die "VERIFY_NO_BLOCKS" }
$blockRoot = MerkleRootHex $blkSorted
if($blockRoot -ne $expectedBlock){ Die ("BLOCK_ROOT_MISMATCH: expected=" + $expectedBlock + " got=" + $blockRoot) }

# 2) verify semantic_root (entry order)
$ehs = New-Object System.Collections.Generic.List[string]
foreach($e in $entries){
  $t = [string]$e.type
  $p = [string]$e.path
  if([string]::IsNullOrWhiteSpace($t) -or [string]::IsNullOrWhiteSpace($p)){ Die "ENTRY_SHAPE_INVALID" }
  if($t -eq "dir"){
    [void]$ehs.Add((EntryHashV1 "dir" $p 0 ""))
  } elseif($t -eq "file"){
    $len = [int64]$e.length
    $sha = [string]$e.sha256
    if($sha -notmatch "^[0-9a-f]{64}$"){ Die ("FILE_SHA_SHAPE_INVALID: " + $p) }
    [void]$ehs.Add((EntryHashV1 "file" $p $len $sha))
  } else {
    Die ("ENTRY_TYPE_UNEXPECTED: " + $t)
  }
}
$semanticRoot = MerkleRootHex ($ehs.ToArray())
if($semanticRoot -ne $expectedSemantic){ Die ("SEMANTIC_ROOT_MISMATCH: expected=" + $expectedSemantic + " got=" + $semanticRoot) }

# 3) verify tmp tree files match manifest sha/len; count dirs/files/bytes
$seenFiles = 0
$seenDirs  = 0
$seenBytes = [int64]0

foreach($e in $entries){
  $t = [string]$e.type
  $rel= [string]$e.path
  $dst = Join-Path $TmpDir ($rel -replace "/","\")
  if($t -eq "dir"){
    if(-not (Test-Path -LiteralPath $dst -PathType Container)){ Die ("TMP_DIR_MISSING: " + $rel) }
    $seenDirs++
  } elseif($t -eq "file"){
    if(-not (Test-Path -LiteralPath $dst -PathType Leaf)){ Die ("TMP_FILE_MISSING: " + $rel) }
    $len = [int64]$e.length
    $sha = [string]$e.sha256
    $actualLen = (Get-Item -LiteralPath $dst).Length
    if([int64]$actualLen -ne $len){ Die ("TMP_FILE_LEN_MISMATCH: " + $rel) }
    $actualSha = Sha256HexFile $dst
    if($actualSha -ne $sha){ Die ("TMP_FILE_SHA_MISMATCH: " + $rel) }
    $seenFiles++
    $seenBytes += $len
  }
}

if($seenFiles -ne $expectedFiles){ Die ("TMP_FILE_COUNT_MISMATCH: got=" + $seenFiles + " expected=" + $expectedFiles) }
if($seenDirs  -ne $expectedDirs ){ Die ("TMP_DIR_COUNT_MISMATCH: got=" + $seenDirs  + " expected=" + $expectedDirs) }
if($seenBytes -ne $expectedBytes){ Die ("TMP_TOTAL_BYTES_MISMATCH: got=" + $seenBytes + " expected=" + $expectedBytes) }

Write-Host "OK: TRIAD RESTORE TREE VERIFY v1" -ForegroundColor Green
Write-Host ("plan:          {0}" -f $PlanPath)       -ForegroundColor Cyan
Write-Host ("semantic_root: {0}" -f $semanticRoot)   -ForegroundColor DarkGray
Write-Host ("block_root:    {0}" -f $blockRoot)      -ForegroundColor DarkGray
Write-Host ("files/dirs/bytes ok: {0}/{1}/{2}" -f $seenFiles,$seenDirs,$seenBytes) -ForegroundColor DarkGray

$semanticRoot
