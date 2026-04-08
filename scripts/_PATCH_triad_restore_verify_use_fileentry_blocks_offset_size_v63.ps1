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
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v63_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force
Write-Host ("backupdir: " + $BackupDir) -ForegroundColor DarkGray

$raw = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
if($raw -match 'PATCH_FILEENTRY_BLOCKS_OFFSET_SIZE_V63'){
  Parse-GateFile_Parser $Target
  Write-Host ("OK: v63 already present: " + $Target) -ForegroundColor Green
  return
}

# 1) Insert helper to find canonical payload file entry
if($raw -notmatch '(?im)^\s*function\s+GetPayloadFileEntryForVerify\s*\('){
  $anchor = [regex]::Match($raw, '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
  if(-not $anchor.Success){ Die "NO_SET_STRICTMODE_ANCHOR_FOUND_V63" }
  $pos = $anchor.Index + $anchor.Length

  $helper = @"
# PATCH_FILEENTRY_BLOCKS_OFFSET_SIZE_V63
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
# /PATCH_FILEENTRY_BLOCKS_OFFSET_SIZE_V63

"@
  $raw = $raw.Substring(0,$pos) + "`n" + $helper + $raw.Substring($pos)
}

# 2) Replace expected contract derivation
$patternExpected = '(?is)\$expectedLen\s*=\s*\[int64\]\(PropOf \$man\.source "total_bytes"\)\s*\r?\n\s*\$expectedSha\s*=\s*\[string\]\(PropOf \$man\.roots "semantic_root"\)\s*\r?\n\s*\$expectedRoot\s*=\s*\[string\]\(PropOf \$man\.roots "block_root"\)'
$replacementExpected = @"
`$payloadEntry = GetPayloadFileEntryForVerify `$man
if(`$null -eq `$payloadEntry){ Die "PAYLOAD_ENTRY_NOT_FOUND_V63" }

`$expectedLen  = [int64](PropOf `$payloadEntry "length")
`$expectedSha  = [string](PropOf `$payloadEntry "sha256")
`$payloadRoots = PropOf `$payloadEntry "roots"
`$expectedRoot = [string](PropOf `$payloadRoots "block_root")
Write-Host ("TRACE_PAYLOAD_ENTRY_V63: path=" + [string](PropOf `$payloadEntry "path")) -ForegroundColor DarkGray
Write-Host ("TRACE_EXPECTED_FROM_ENTRY_V63: len=" + `$expectedLen + " sha=" + `$expectedSha + " root=" + `$expectedRoot) -ForegroundColor DarkGray
"@
$raw2 = [regex]::Replace($raw, $patternExpected, $replacementExpected, 1)
if($raw2 -eq $raw){ Die "EXPECTED_CONTRACT_BLOCK_NOT_FOUND_V63" }
$raw = $raw2

# 3) Replace block selection line
$patternBlocks = '(?im)^\s*\$blocks\s*=\s*@\(@\(\(GetBlocksForVerify \$man \$plan\)\)\)\s*$'
$replacementBlocks = @"
`$blocks = @(@(PropOf `$payloadEntry "blocks"))
if(@(@(`$blocks)).Count -lt 1){
  `$blocks = @(@((GetBlocksForVerify `$man `$plan)))
}
"@
$raw2 = [regex]::Replace($raw, $patternBlocks, $replacementBlocks, 1)
if($raw2 -eq $raw){ Die "BLOCKS_LINE_NOT_FOUND_V63" }
$raw = $raw2

# 4) Replace v62 rebuild block with offset/size aware payload-entry rebuild
$patternRebuild = '(?is)# PATCH_REBUILD_TMP_FROM_BLOCKS_V62.*?# /PATCH_REBUILD_TMP_FROM_BLOCKS_V62'
$replacementRebuild = @"
# PATCH_REBUILD_TMP_FROM_BLOCKS_V62
# PATCH_FILEENTRY_BLOCKS_OFFSET_SIZE_V63
`$tmpLen = (Get-Item -LiteralPath `$TmpFile).Length
if(([int64]`$tmpLen -eq 0) -and (@(@(`$blocks)).Count -gt 0)){
  Write-Host "TRACE_REBUILD_TMP_FROM_FILEENTRY_BLOCKS_V63" -ForegroundColor DarkGray

  `$orderedBlocks = @(
    @(@(`$blocks)) |
      Sort-Object `
        @{ Expression = { try { [int64](PropOf `$_ "index") } catch { [int64]::MaxValue } } }, `
        @{ Expression = { try { [int64](PropOf `$_ "offset") } catch { [int64]::MaxValue } } }
  )

  `$fs = `$null
  try {
    `$fs = New-Object System.IO.FileStream(`$TmpFile,[System.IO.FileMode]::Create,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)

    foreach(`$b in `$orderedBlocks){
      `$rel    = [string](PropOf `$b "path")
      `$offset = [int64](PropOf `$b "offset")
      `$size   = [int64](PropOf `$b "size")
      `$sha    = [string](PropOf `$b "sha256")
      `$index  = [int64](PropOf `$b "index")

      if([string]::IsNullOrWhiteSpace(`$rel)){ Die "TMP_REBUILD_BLOCK_PATH_MISSING_V63" }
      if(`$offset -lt 0){ Die ("TMP_REBUILD_BLOCK_OFFSET_NEGATIVE_V63: " + `$offset) }
      if(`$size -lt 0){ Die ("TMP_REBUILD_BLOCK_SIZE_NEGATIVE_V63: " + `$size) }

      `$blkPath = Join-Path `$SnapshotDir (`$rel -replace "/","\")
      if(-not (Test-Path -LiteralPath `$blkPath -PathType Leaf)){ Die ("TMP_REBUILD_MISSING_BLOCK_FILE_V63: " + `$blkPath) }

      `$bytes = [System.IO.File]::ReadAllBytes(`$blkPath)
      `$actualBlkSha = Sha256HexFile `$blkPath
      if(`$actualBlkSha -ne `$sha){ Die ("TMP_REBUILD_BLOCK_SHA_MISMATCH_V63: expected=" + `$sha + " got=" + `$actualBlkSha + " file=" + `$blkPath) }

      if([int64]`$bytes.Length -lt `$size){
        Die ("TMP_REBUILD_BLOCK_TOO_SHORT_V63: index=" + `$index + " size=" + `$size + " bytes=" + `$bytes.Length + " file=" + `$blkPath)
      }

      `$fs.Position = `$offset
      `$fs.Write(`$bytes,0,[int]`$size)
      Write-Host ("TRACE_REBUILD_BLOCK_V63: index=" + `$index + " offset=" + `$offset + " size=" + `$size + " sha=" + `$sha) -ForegroundColor DarkGray
    }

    `$fs.SetLength([int64]`$expectedLen)
    `$fs.Flush()
  } finally {
    if(`$null -ne `$fs){ `$fs.Dispose() }
  }

  `$tmpLen = (Get-Item -LiteralPath `$TmpFile).Length
  Write-Host ("TRACE_REBUILT_TMP_LEN_V63: " + `$tmpLen) -ForegroundColor DarkGray
}
# /PATCH_FILEENTRY_BLOCKS_OFFSET_SIZE_V63
# /PATCH_REBUILD_TMP_FROM_BLOCKS_V62
"@
$raw2 = [regex]::Replace($raw, $patternRebuild, $replacementRebuild, 1)
if($raw2 -eq $raw){ Die "REBUILD_PATCH_BLOCK_NOT_FOUND_V63" }
$raw = $raw2

Write-Utf8NoBomLf $Target $raw
Parse-GateFile_Parser $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v63: use file-entry blocks with offset/size rebuild)") -ForegroundColor Green
