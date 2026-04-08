param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Parse-GateText_Parser([string]$Text){
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tok,[ref]$err)
  $errs = @()
  if($err -ne $null){ $errs = @(@($err)) }
  if($errs.Count -gt 0){
    $msg = ($errs | Select-Object -First 12 | ForEach-Object { $_.Message }) -join " | "
    throw ("PARSE_GATE_FAIL: " + $msg)
  }
}

function Parse-GateFile_Parser([string]$Path){
  $raw0 = (Get-Content -Raw -LiteralPath $Path -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
  Parse-GateText_Parser $raw0
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
if(-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)){ Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){ Die ("MISSING_TARGET: " + $Target) }

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v63r_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".broken_pre_restore")) -Force
Write-Host ("backupdir: " + $BackupDir) -ForegroundColor DarkGray

# ------------------------------------------------------------
# Restore newest parse-ok pre_patch backup
# ------------------------------------------------------------
$Candidates = Get-ChildItem -LiteralPath $ScriptsDir -Directory -Force |
  Where-Object { $_.Name -like "_backup_triad_restore_verify_*" } |
  Sort-Object FullName -Descending

$GoodPath = ""
$checked = 0
foreach($d in $Candidates){
  $p = Join-Path $d.FullName "triad_restore_verify_v1.ps1.pre_patch"
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ continue }
  $checked++
  $rawTry = (Get-Content -Raw -LiteralPath $p -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
  try {
    Parse-GateText_Parser $rawTry
    $GoodPath = $p
    break
  } catch {
    continue
  }
}

Write-Host ("checked_prepatch: " + $checked) -ForegroundColor DarkGray
if([string]::IsNullOrWhiteSpace($GoodPath)){ Die "NO_PARSE_OK_PRE_PATCH_FOUND_V63R" }

Write-Host ("restore_from: " + $GoodPath) -ForegroundColor DarkGray
$rest = (Get-Content -Raw -LiteralPath $GoodPath -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
Write-Utf8NoBomLf $Target $rest
Parse-GateFile_Parser $Target
Write-Host ("RESTORED_OK: " + $Target) -ForegroundColor Green

$raw = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
if($raw -match 'PATCH_FILEENTRY_BLOCKS_OFFSET_SIZE_V63R'){
  Parse-GateFile_Parser $Target
  Write-Host ("OK: v63r already present: " + $Target) -ForegroundColor Green
  return
}

# ------------------------------------------------------------
# 1) Insert helper after Set-StrictMode
# ------------------------------------------------------------
if($raw -notmatch '(?im)^\s*function\s+GetPayloadFileEntryForVerify\s*\('){
  $anchor = [regex]::Match($raw, '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
  if(-not $anchor.Success){ Die "NO_SET_STRICTMODE_ANCHOR_FOUND_V63R" }
  $pos = $anchor.Index + $anchor.Length

  $helper = @"
# PATCH_FILEENTRY_BLOCKS_OFFSET_SIZE_V63R
function GetPayloadFileEntryForVerify([Parameter(Mandatory=`$true)]`$Manifest){
  `$entries = @()
  try { `$entries = @(@(PropOf `$Manifest "entries")) } catch { `$entries = @() }

  foreach(`$e in `$entries){
    if(`$null -eq `$e){ continue }
    `$type = ""
    `$path = ""
    try { `$type = [string](PropOf `$e "type") } catch { `$type = "" }
    try { `$path = [string](PropOf `$e "path") } catch { `$path = "" }
    if(`$type -eq "file" -and `$path -eq "payload.bin"){ return `$e }
  }

  foreach(`$e in `$entries){
    if(`$null -eq `$e){ continue }
    `$type = ""
    try { `$type = [string](PropOf `$e "type") } catch { `$type = "" }
    if(`$type -ne "file"){ continue }
    `$b = @()
    try { `$b = @(@(PropOf `$e "blocks")) } catch { `$b = @() }
    if(`$b.Count -gt 0){ return `$e }
  }

  return `$null
}
# /PATCH_FILEENTRY_BLOCKS_OFFSET_SIZE_V63R

"@
  $raw = $raw.Substring(0,$pos) + "`n" + $helper + $raw.Substring($pos)
}

# ------------------------------------------------------------
# 2) Replace expected contract derivation
# ------------------------------------------------------------
$raw = $raw.Replace(
  '$expectedLen  = [int64](PropOf $man.source "total_bytes")' + "`n" +
  '$expectedSha  = [string](PropOf $man.roots "semantic_root")' + "`n" +
  '$expectedRoot = [string](PropOf $man.roots "block_root")',
  '$payloadEntry = GetPayloadFileEntryForVerify $man' + "`n" +
  'if($null -eq $payloadEntry){ Die "PAYLOAD_ENTRY_NOT_FOUND_V63R" }' + "`n" +
  '$expectedLen  = [int64](PropOf $payloadEntry "length")' + "`n" +
  '$expectedSha  = [string](PropOf $payloadEntry "sha256")' + "`n" +
  '$payloadRoots = PropOf $payloadEntry "roots"' + "`n" +
  '$expectedRoot = [string](PropOf $payloadRoots "block_root")' + "`n" +
  'Write-Host ("TRACE_PAYLOAD_ENTRY_V63R: path=" + [string](PropOf $payloadEntry "path")) -ForegroundColor DarkGray' + "`n" +
  'Write-Host ("TRACE_EXPECTED_FROM_ENTRY_V63R: len=" + $expectedLen + " sha=" + $expectedSha + " root=" + $expectedRoot) -ForegroundColor DarkGray'
)

if($raw -notmatch 'TRACE_PAYLOAD_ENTRY_V63R'){ Die "EXPECTED_CONTRACT_REWRITE_FAILED_V63R" }

# ------------------------------------------------------------
# 3) Replace block selection line
# ------------------------------------------------------------
$raw = $raw.Replace(
  '$blocks = @(@((GetBlocksForVerify $man $plan)))',
  '$blocks = @(@(PropOf $payloadEntry "blocks"))' + "`n" +
  'if(@(@($blocks)).Count -lt 1){' + "`n" +
  '  $blocks = @(@((GetBlocksForVerify $man $plan)))' + "`n" +
  '}'
)

if($raw -notmatch '(?im)^\s*\$blocks\s*=\s*@\(@\(PropOf \$payloadEntry "blocks"\)\)\s*$'){
  Die "BLOCKS_REWRITE_FAILED_V63R"
}

# ------------------------------------------------------------
# 4) Replace v62 rebuild block by marker slice
# ------------------------------------------------------------
$startMarker = '# PATCH_REBUILD_TMP_FROM_BLOCKS_V62'
$endMarker   = '# /PATCH_REBUILD_TMP_FROM_BLOCKS_V62'
$startIdx = $raw.IndexOf($startMarker)
$endIdx   = $raw.IndexOf($endMarker)

if($startIdx -lt 0){ Die "REBUILD_START_MARKER_NOT_FOUND_V63R" }
if($endIdx -lt 0){ Die "REBUILD_END_MARKER_NOT_FOUND_V63R" }
if($endIdx -le $startIdx){ Die "REBUILD_MARKER_ORDER_INVALID_V63R" }

$endIdx2 = $endIdx + $endMarker.Length

$newBlock = @"
# PATCH_REBUILD_TMP_FROM_BLOCKS_V62
# PATCH_FILEENTRY_BLOCKS_OFFSET_SIZE_V63R
`$tmpLen = (Get-Item -LiteralPath `$TmpFile).Length
if(([int64]`$tmpLen -eq 0) -and (@(@(`$blocks)).Count -gt 0)){
  Write-Host "TRACE_REBUILD_TMP_FROM_FILEENTRY_BLOCKS_V63R" -ForegroundColor DarkGray

  `$orderedBlocks = @(@(`$blocks) | Sort-Object index, offset)

  `$fs = `$null
  try {
    `$fs = New-Object System.IO.FileStream(`$TmpFile,[System.IO.FileMode]::Create,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)

    foreach(`$b in `$orderedBlocks){
      `$rel    = [string](PropOf `$b "path")
      `$offset = [int64](PropOf `$b "offset")
      `$size   = [int64](PropOf `$b "size")
      `$sha    = [string](PropOf `$b "sha256")
      `$index  = [int64](PropOf `$b "index")

      if([string]::IsNullOrWhiteSpace(`$rel)){ Die "TMP_REBUILD_BLOCK_PATH_MISSING_V63R" }
      if(`$offset -lt 0){ Die ("TMP_REBUILD_BLOCK_OFFSET_NEGATIVE_V63R: " + `$offset) }
      if(`$size -lt 0){ Die ("TMP_REBUILD_BLOCK_SIZE_NEGATIVE_V63R: " + `$size) }

      `$blkPath = Join-Path `$SnapshotDir (`$rel -replace "/","\")
      if(-not (Test-Path -LiteralPath `$blkPath -PathType Leaf)){ Die ("TMP_REBUILD_MISSING_BLOCK_FILE_V63R: " + `$blkPath) }

      `$bytes = [System.IO.File]::ReadAllBytes(`$blkPath)
      `$actualBlkSha = Sha256HexFile `$blkPath
      if(`$actualBlkSha -ne `$sha){ Die ("TMP_REBUILD_BLOCK_SHA_MISMATCH_V63R: expected=" + `$sha + " got=" + `$actualBlkSha + " file=" + `$blkPath) }

      if([int64]`$bytes.Length -lt `$size){
        Die ("TMP_REBUILD_BLOCK_TOO_SHORT_V63R: index=" + `$index + " size=" + `$size + " bytes=" + `$bytes.Length + " file=" + `$blkPath)
      }

      `$fs.Position = `$offset
      `$fs.Write(`$bytes,0,[int]`$size)
      Write-Host ("TRACE_REBUILD_BLOCK_V63R: index=" + `$index + " offset=" + `$offset + " size=" + `$size + " sha=" + `$sha) -ForegroundColor DarkGray
    }

    `$fs.SetLength([int64]`$expectedLen)
    `$fs.Flush()
  } finally {
    if(`$null -ne `$fs){ `$fs.Dispose() }
  }

  `$tmpLen = (Get-Item -LiteralPath `$TmpFile).Length
  Write-Host ("TRACE_REBUILT_TMP_LEN_V63R: " + `$tmpLen) -ForegroundColor DarkGray
}
# /PATCH_FILEENTRY_BLOCKS_OFFSET_SIZE_V63R
# /PATCH_REBUILD_TMP_FROM_BLOCKS_V62
"@

$raw = $raw.Substring(0,$startIdx) + $newBlock + $raw.Substring($endIdx2)

Write-Utf8NoBomLf $Target $raw
Parse-GateFile_Parser $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v63r: payload file-entry blocks with offset/size rebuild)") -ForegroundColor Green
