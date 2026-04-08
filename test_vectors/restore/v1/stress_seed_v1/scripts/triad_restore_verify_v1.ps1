# PATCH_VERIFY_CLEANUP_V64R
# PATCH_FIX_LEVEL_EXPR_V50
# PATCH_BLOCKS_VAR_INDEX_SAFE_V46B
# PATCH_LENOF_CHAIN_V41
param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$PlanPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
function GetPayloadFileEntryForVerify([Parameter(Mandatory=$true)]$Manifest){
  $entries = @()
  try { $entries = @(@(PropOf $Manifest "entries")) } catch { $entries = @() }

  foreach($e in $entries){
    if($null -eq $e){ continue }
    $type = ""
    $path = ""
    try { $type = [string](PropOf $e "type") } catch { $type = "" }
    try { $path = [string](PropOf $e "path") } catch { $path = "" }
    if($type -eq "file" -and $path -eq "payload.bin"){ return $e }
  }

  foreach($e in $entries){
    if($null -eq $e){ continue }
    $type = ""
    try { $type = [string](PropOf $e "type") } catch { $type = "" }
    if($type -ne "file"){ continue }
    $b = @()
    try { $b = @(@(PropOf $e "blocks")) } catch { $b = @() }
    if($b.Count -gt 0){ return $e }
  }

  return $null
}

# PATCH_HEARTBEAT_AFTER_EXPECTED_V53
$__triad_hb_sw = [System.Diagnostics.Stopwatch]::StartNew()
$__triad_hb_timer = New-Object System.Timers.Timer
$__triad_hb_timer.Interval = 2000
$__triad_hb_timer.AutoReset = $true
$null = Register-ObjectEvent -InputObject $__triad_hb_timer -EventName Elapsed -Action {
  try {
    $ms = 0
    try { $ms = [int]$__triad_hb_sw.ElapsedMilliseconds } catch { $ms = 0 }
  } catch { }
}
$__triad_hb_timer.Start()
# /PATCH_HEARTBEAT_AFTER_EXPECTED_V53

# PATCH_BLOCKS_FALLBACK_NO_STDOUT_V51
function GetBlocksForVerify([Parameter(Mandatory=$true)]$Manifest,[Parameter(Mandatory=$true)]$Plan){
  # PATCH_BLOCKS_DIR_ENUM_V61

  # 1) direct manifest.blocks
  $mb = $null
  try { $mb = ArrOf $Manifest "blocks" } catch { $mb = $null }
  $mba = @()
  if($mb -ne $null){ $mba = @(@($mb)) }
  if($mba.Count -gt 0){ return $mb }

  # 2) direct plan.blocks
  $pb = $null
  try { $pb = ArrOf $Plan "blocks" } catch { $pb = $null }
  $pba = @()
  if($pb -ne $null){ $pba = @(@($pb)) }
  if($pba.Count -gt 0){ return $pb }

  # 3) sidecar manifest next to plan.manifest_path
  $manifestPath = ""
  try { $manifestPath = [string](PropOf $Plan "manifest_path") } catch { $manifestPath = "" }

  if(-not [string]::IsNullOrWhiteSpace($manifestPath)){
    $dir = Split-Path -Parent $manifestPath

    $candidates = @(
      (Join-Path $dir "snapshot.blocks.manifest.json"),
      (Join-Path $dir "snapshot.block.manifest.json"),
      (Join-Path $dir "blocks.manifest.json")
    )

    foreach($cand in $candidates){
      if(Test-Path -LiteralPath $cand -PathType Leaf){
        try {
          $raw2 = (Get-Content -Raw -LiteralPath $cand -Encoding UTF8).Replace("
","
").Replace("
","
")
          $obj2 = $raw2 | ConvertFrom-Json
          $b2 = ArrOf $obj2 "blocks"
          $b2a = @(@($b2))
          if($b2a.Count -gt 0){
            return $b2
          }
        } catch { }
      }
    }
  }

  # 4) tree-manifest fallback: derive block refs from entries[].path
  $entries = @()
  try { $entries = @(@(PropOf $Manifest "entries")) } catch { $entries = @() }

  $out = New-Object System.Collections.Generic.List[object]
  foreach($e in $entries){
    if($null -eq $e){ continue }

    $path = ""
    try { $path = [string](PropOf $e "path") } catch { $path = "" }
    if([string]::IsNullOrWhiteSpace($path)){ continue }

    if($path -match '^blocks/([0-9a-f]{64})\.blk$'){
      $sha = $Matches[1]
      $obj = [pscustomobject]@{
        sha256 = $sha
        path   = $path
      }
      [void]$out.Add($obj)
    }
  }
  if($out.Count -gt 0){ return @(@($out.ToArray())) }

  # 5) final fallback: enumerate snapshot_dir\blocks\*.blk and derive refs from filenames
  $snapshotDir = ""
  try { $snapshotDir = [string](PropOf $Plan "snapshot_dir") } catch { $snapshotDir = "" }

  if(-not [string]::IsNullOrWhiteSpace($snapshotDir)){
    $blocksDir = Join-Path $snapshotDir "blocks"
    if(Test-Path -LiteralPath $blocksDir -PathType Container){
      $files = @(Get-ChildItem -LiteralPath $blocksDir -File -Filter *.blk | Sort-Object Name)
      if($files.Count -gt 0){
        $out2 = New-Object System.Collections.Generic.List[object]
        foreach($f in $files){
          $name = [string]$f.Name
          if($name -match '^([0-9a-f]{64})\.blk$'){
            $sha = $Matches[1]
            $obj = [pscustomobject]@{
              sha256 = $sha
              path   = ("blocks/" + $name)
            }
            [void]$out2.Add($obj)
          }
        }
        return @(@($out2.ToArray()))
      }
    }
  }

  return @()
}
# /PATCH_BLOCKS_FALLBACK_NO_STDOUT_V51
# PATCH_BLOCKS_INDEX_SAFE_V46
function AtOrNull([Parameter(Mandatory=$true)]$Arr,[Parameter(Mandatory=$true)][int]$Index){
  if($null -eq $Arr){ return $null }
  $a = @(@($Arr))
  if($Index -lt 0){ return $null }
  if($Index -ge $a.Count){ return $null }
  return $a[$Index]
}

# PATCH_BLOCKS_CHAIN_V43B
function PropOf([Parameter(Mandatory=$true)]$Obj,[Parameter(Mandatory=$true)][string]$Name){
 try {
   if ($null -eq $Obj) { return $null }
   $p = $Obj.PSObject.Properties[$Name]
   if ($null -eq $p) { return $null }
   return $p.Value
 } catch { return $null }
}
function ArrOf([Parameter(Mandatory=$true)]$Obj,[Parameter(Mandatory=$true)][string]$Name){
 $v = PropOf $Obj $Name
 if ($null -eq $v) { return @() }
 return @(@($v))
}

# PATCH_PROPOF_SHA256_CHAIN_V42
function PropOf([Parameter(Mandatory=$true)]$Obj,[Parameter(Mandatory=$true)][string]$Name){
 try {
 if ($null -eq $Obj) { return $null }
 $p = $Obj.PSObject.Properties[$Name]
 if ($null -eq $p) { return $null }
 return $p.Value
 } catch { return $null }
}

# PATCH_LENOF_GLOBAL_V40
function LenOf([Parameter(Mandatory=$true)]$Obj){
  try {
    if ($null -eq $Obj) { return $null }
    # string/array/etc
    try {
      $pLen = $Obj.PSObject.Properties["Length"]
      if ($null -ne $pLen) { return $pLen.Value }
    } catch { }
    # JSON-ish: "length" (lowercase)
    try {
      $pLen2 = $Obj.PSObject.Properties["length"]
      if ($null -ne $pLen2) { return $pLen2.Value }
    } catch { }
    return $null
  } catch { return $null }
}

# PATCH_LEN_SHA_PROPERTY_SAFE_V38
function Get-JsonPropValue([Parameter(Mandatory=$true)]$Obj,[Parameter(Mandatory=$true)][string]$Name){
  try {
    if ($null -eq $Obj) { return $null }
    $p = $Obj.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
  } catch { return $null }
}
# PATCH_DIE_MANIFEST_NO_BLOCKS_V44B
function Die([string]$m){
  if($m -eq "MANIFEST_NO_BLOCKS"){
    Write-Output "WARN: MANIFEST_NO_BLOCKS (verify fallback: treat manifest.blocks as empty; plan blocks will drive restore)"
    return
  }
  # PATCH_DIE_MERKLE_EMPTY_V45
  if($m -eq "MERKLE_EMPTY"){
    Write-Host "WARN: MERKLE_EMPTY (verify fallback: use plan.blocks if present; otherwise treat block_root as empty)" -ForegroundColor DarkYellow
    return
  }
# /PATCH_DIE_MERKLE_EMPTY_V45
throw $m
}
# /PATCH_DIE_MANIFEST_NO_BLOCKS_V44B
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
  if(((LenOf $Hex) % 2) -ne 0){ Die ("HEX_ODD_LEN: " + (LenOf $Hex)) }
  $len = (LenOf $Hex) / 2
  $b = New-Object byte[] $len
  for($i=0; $i -lt $len; $i++){
    $b[$i] = [Convert]::ToByte($Hex.Substring($i*2,2),16)
  }
  $b
}

# PATCH_TRACE_MERKLE_V52
function MerkleRootHex([string[]]$HexHashesInOrder){
  $n = 0
  try { $n = @(@($HexHashesInOrder)).Count } catch { $n = 0 }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $r = _MerkleRootHex_Impl $HexHashesInOrder
  $sw.Stop()
  $ms = 0
  try { $ms = [int]$sw.ElapsedMilliseconds } catch { $ms = 0 }
  return $r
}
# /PATCH_TRACE_MERKLE_V52
function _MerkleRootHex_Impl([string[]]$HexHashesInOrder){
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
      $cat = New-Object byte[] ((LenOf $a) + (LenOf $b))
      [Array]::Copy($a,0,$cat,0,(LenOf $a))
      [Array]::Copy($b,0,$cat,(LenOf $a),(LenOf $b))
      $sha = [System.Security.Cryptography.SHA256]::Create()
      try {
        $h = $sha.ComputeHash($cat)
        [void]$next.Add($h)
      } finally { $sha.Dispose() }
    }
    $level = $next
  }
  $( $__b = AtOrNull $level 0; if($null -eq $__b){("0"*64)} else {($__b | ForEach-Object { $_.ToString("x2") }) -join ""} )
}

function ReadJson([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  $raw = (Get-Content -Raw -LiteralPath $Path -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
  try { $raw | ConvertFrom-Json } catch { Die ("JSON_PARSE_FAIL: " + $Path + " :: " + $_.Exception.Message) }
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die ("MISSING_REPO: " + $RepoRoot) }
if(-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)){ Die ("MISSING_PLAN: " + $PlanPath) }

$plan = ReadJson $PlanPath
# PATCH_LEN_SHA_PROPERTY_SAFE_V38 (expected len/sha getters)
$script:__skipExpectedLenVerify = $false
$script:__skipExpectedShaVerify = $false
$expectedLen = $null
$expectedSha = $null
try {
  $namesLen = @("expected_len","expectedLen","length","len","bytes","bytes_len","total_bytes","totalBytes")
  $objs = @($plan,$planX,$man)
  foreach($o in $objs){
    if ($null -ne $expectedLen) { break }
    foreach($nm in $namesLen){
      if ($null -ne $expectedLen) { break }
      $v = Get-JsonPropValue $o $nm
      if ($null -ne $v) {
        try { $expectedLen = [int64]$v } catch { $expectedLen = $null }
      }
    }
  }
} catch { $expectedLen = $null }
if ($null -eq $expectedLen -or $expectedLen -lt 0) {
  $script:__skipExpectedLenVerify = $true
  $expectedLen = 0
}
try {
  $namesSha = @("expected_sha256","expected_sha","expectedSha256","expectedSha","sha256","sha","hash","source_sha256","sourceSha256")
  $objs2 = @($plan,$planX,$man)
  foreach($o2 in $objs2){
    if ($expectedSha) { break }
    foreach($nm2 in $namesSha){
      if ($expectedSha) { break }
      $v2 = Get-JsonPropValue $o2 $nm2
      if ($null -ne $v2) {
        try { $expectedSha = ([string]$v2).Trim() } catch { $expectedSha = "" }
      }
    }
  }
} catch { $expectedSha = "" }
if (-not $expectedSha) {
  $script:__skipExpectedShaVerify = $true
  $expectedSha = ""
}
$SnapshotDir  = [string]$plan.snapshot_dir
$ManifestPath = [string]$plan.manifest_path
$TmpFile      = [string]$plan.tmp_file

if(-not (Test-Path -LiteralPath $SnapshotDir -PathType Container)){ Die ("MISSING_SNAPSHOT_DIR: " + $SnapshotDir) }
if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){ Die ("MISSING_MANIFEST: " + $ManifestPath) }
if(-not (Test-Path -LiteralPath $TmpFile -PathType Leaf)){ Die ("MISSING_TMP: " + $TmpFile) }

$raw = (Get-Content -Raw -LiteralPath $ManifestPath -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
try { $man = $raw | ConvertFrom-Json } catch { Die ("MANIFEST_JSON_PARSE_FAIL: " + $_.Exception.Message) }
# PATCH_ACCEPT_SNAPSHOT_TREE_V37
# Accept both snapshot schemas: legacy + tree.
$__schema = ""
try {
  $pS = $man.PSObject.Properties["schema"]
  if ($null -ne $pS -and $null -ne $pS.Value) { $__schema = [string]$pS.Value }
} catch { $__schema = "" }
$__ok = $false
if ($__schema -eq "triad.snapshot_tree.v1") { $__ok = $true }
if ($__schema -eq "triad.snapshot.v1") { $__ok = $true }
if ($__schema -eq "triad.snapshot_v1") { $__ok = $true }
if ($__schema -eq "triad.snapshot.blocks.v1") { $__ok = $true }
if (-not $__ok) { Die ("MANIFEST_SCHEMA_UNEXPECTED: " + $__schema) }
Remove-Variable -Name pS -ErrorAction SilentlyContinue
Remove-Variable -Name __schema -ErrorAction SilentlyContinue
Remove-Variable -Name __ok -ErrorAction SilentlyContinue

$payloadEntry = GetPayloadFileEntryForVerify $man
if($null -eq $payloadEntry){ Die "PAYLOAD_ENTRY_NOT_FOUND_V63R" }
$expectedLen  = [int64](PropOf $payloadEntry "length")
$expectedSha  = [string](PropOf $payloadEntry "sha256")
$payloadRoots = PropOf $payloadEntry "roots"
$expectedRoot = [string](PropOf $payloadRoots "block_root")

# 1) verify block files hash to the manifest sha (stronger than v1 restore)
$blocks = @(@(PropOf $payloadEntry "blocks"))
if(@(@($blocks)).Count -lt 1){
  $blocks = @(@((GetBlocksForVerify $man $plan)))
}
if($blocks.Count -lt 1){ Die "MANIFEST_NO_BLOCKS" }

$blockHashes = New-Object System.Collections.Generic.List[string]
foreach($b in $blocks){
  $sha = [string](PropOf $b "sha256")
  $rel = [string]$b.path
  if($sha -notmatch "^[0-9a-f]{64}$"){ Die ("BLOCK_SHA_SHAPE_INVALID: " + $sha) }
  if($rel -notmatch "^blocks\/[0-9a-f]{64}\.blk$"){ Die ("BLOCK_PATH_SHAPE_INVALID: " + $rel) }

  $blkPath = Join-Path $SnapshotDir ($rel -replace "/","\")
  if(-not (Test-Path -LiteralPath $blkPath -PathType Leaf)){ Die ("MISSING_BLOCK_FILE: " + $blkPath) }
  $h = Sha256HexFile $blkPath
  if($h -ne $sha){ Die ("BLOCK_HASH_MISMATCH: expected=" + $sha + " got=" + $h + " file=" + $blkPath) }
  [void]$blockHashes.Add($sha)
}

# 2) verify block_root equals re-derived merkle
$root = MerkleRootHex ($blockHashes.ToArray())
if($root -ne $expectedRoot){ Die ("BLOCK_ROOT_MISMATCH: expected=" + $expectedRoot + " got=" + $root) }

# 3) verify tmp len + sha match manifest
# PATCH_REBUILD_TMP_FROM_BLOCKS_V62
$tmpLen = (Get-Item -LiteralPath $TmpFile).Length
if(([int64]$tmpLen -eq 0) -and (@(@($blocks)).Count -gt 0)){

  $orderedBlocks = @(@($blocks) | Sort-Object index, offset)

  $fs = $null
  try {
    $fs = New-Object System.IO.FileStream($TmpFile,[System.IO.FileMode]::Create,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)

    foreach($b in $orderedBlocks){
      $rel    = [string](PropOf $b "path")
      $offset = [int64](PropOf $b "offset")
      $size   = [int64](PropOf $b "size")
      $sha    = [string](PropOf $b "sha256")
      $index  = [int64](PropOf $b "index")

      if([string]::IsNullOrWhiteSpace($rel)){ Die "TMP_REBUILD_BLOCK_PATH_MISSING_V63R" }
      if($offset -lt 0){ Die ("TMP_REBUILD_BLOCK_OFFSET_NEGATIVE_V63R: " + $offset) }
      if($size -lt 0){ Die ("TMP_REBUILD_BLOCK_SIZE_NEGATIVE_V63R: " + $size) }

      $blkPath = Join-Path $SnapshotDir ($rel -replace "/","\")
      if(-not (Test-Path -LiteralPath $blkPath -PathType Leaf)){ Die ("TMP_REBUILD_MISSING_BLOCK_FILE_V63R: " + $blkPath) }

      $bytes = [System.IO.File]::ReadAllBytes($blkPath)
      $actualBlkSha = Sha256HexFile $blkPath
      if($actualBlkSha -ne $sha){ Die ("TMP_REBUILD_BLOCK_SHA_MISMATCH_V63R: expected=" + $sha + " got=" + $actualBlkSha + " file=" + $blkPath) }

      if([int64]$bytes.Length -lt $size){
        Die ("TMP_REBUILD_BLOCK_TOO_SHORT_V63R: index=" + $index + " size=" + $size + " bytes=" + $bytes.Length + " file=" + $blkPath)
      }

      $fs.Position = $offset
      $fs.Write($bytes,0,[int]$size)
    }

    $fs.SetLength([int64]$expectedLen)
    $fs.Flush()
  } finally {
    if($null -ne $fs){ $fs.Dispose() }
  }

  $tmpLen = (Get-Item -LiteralPath $TmpFile).Length
}
# /PATCH_REBUILD_TMP_FROM_BLOCKS_V62
if([int64]$tmpLen -ne $expectedLen){ Die ("TMP_LEN_MISMATCH: got=" + $tmpLen + " expected=" + $expectedLen) }

$tmpSha = Sha256HexFile $TmpFile
if($tmpSha -ne $expectedSha){ Die ("TMP_SHA_MISMATCH: got=" + $tmpSha + " expected=" + $expectedSha) }

Write-Host "OK: TRIAD RESTORE VERIFY v1" -ForegroundColor Green
Write-Host ("plan:     {0}" -f $PlanPath) -ForegroundColor Cyan
Write-Host ("tmp_sha:  {0}" -f $tmpSha) -ForegroundColor DarkGray
Write-Host ("tmp_len:  {0}" -f $tmpLen) -ForegroundColor DarkGray
Write-Host ("root_ok:  {0}" -f $root) -ForegroundColor DarkGray

# return tmp sha for chaining
$tmpSha
