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
  $raw = (Get-Content -Raw -LiteralPath $Path -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
  Parse-GateText_Parser $raw
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
if(-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)){ Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){ Die ("MISSING_TARGET: " + $Target) }

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v59_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force
Write-Host ("backupdir: " + $BackupDir) -ForegroundColor DarkGray

$raw = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")
if($raw -match 'PATCH_TREE_MANIFEST_ENTRIES_EXPECTED_V59'){
  Parse-GateFile_Parser $Target
  Write-Host ("OK: v59 already present: " + $Target) -ForegroundColor Green
  return
}

# ------------------------------------------------------------------
# 1) Replace GetBlocksForVerify with tree-manifest-aware implementation
# ------------------------------------------------------------------
$fnPat = '(?is)function\s+GetBlocksForVerify\s*\(\s*\[Parameter\(Mandatory=\$true\)\]\$Manifest\s*,\s*\[Parameter\(Mandatory=\$true\)\]\$Plan\s*\)\s*\{\s*.*?\n\}'
$fm = [regex]::Match($raw, $fnPat)
if(-not $fm.Success){ Die "GETBLOCKS_FUNCTION_NOT_FOUND_V59" }

$fnNew = @"
function GetBlocksForVerify([Parameter(Mandatory=`$true)]`$Manifest,[Parameter(Mandatory=`$true)]`$Plan){
  # PATCH_TREE_MANIFEST_ENTRIES_EXPECTED_V59

  # 1) direct manifest.blocks
  `$mb = `$null
  try { `$mb = ArrOf `$Manifest "blocks" } catch { `$mb = `$null }
  `$mba = @()
  if(`$mb -ne `$null){ `$mba = @(@(`$mb)) }
  if(`$mba.Count -gt 0){ return `$mb }

  # 2) direct plan.blocks
  `$pb = `$null
  try { `$pb = ArrOf `$Plan "blocks" } catch { `$pb = `$null }
  `$pba = @()
  if(`$pb -ne `$null){ `$pba = @(@(`$pb)) }
  if(`$pba.Count -gt 0){ return `$pb }

  # 3) tree-manifest fallback: derive block refs from Manifest.entries[].path
  #    expected entry shape: { type, path } where path like blocks/<sha>.blk
  `$entries = @()
  try { `$entries = @(@(PropOf `$Manifest "entries")) } catch { `$entries = @() }

  `$out = New-Object System.Collections.Generic.List[object]

  foreach(`$e in `$entries){
    if(`$null -eq `$e){ continue }

    `$path = ""
    try { `$path = [string](PropOf `$e "path") } catch { `$path = "" }

    if([string]::IsNullOrWhiteSpace(`$path)){ continue }

    if(`$path -match '^blocks/([0-9a-f]{64})\.blk$'){
      `$sha = `$Matches[1]
      `$obj = [pscustomobject]@{
        sha256 = `$sha
        path   = `$path
      }
      [void]`$out.Add(`$obj)
    }
  }

  return @(@(`$out.ToArray()))
}
"@

$raw2 = $raw.Substring(0,$fm.Index) + $fnNew + $raw.Substring($fm.Index + $fm.Length)

# ------------------------------------------------------------------
# 2) Fix expected contract derivation lines for tree manifests
#    old:
#      $expectedLen  = [int64](LenOf $man.source)
#      $expectedSha  = [string](PropOf $man.source "sha256")
#      $expectedRoot = [string]$man.roots.block_root
#    new:
#      $expectedLen  = [int64](PropOf $man.source "total_bytes")
#      $expectedSha  = [string](PropOf $man.roots "semantic_root")
#      $expectedRoot = [string](PropOf $man.roots "block_root")
# ------------------------------------------------------------------
$lines = New-Object System.Collections.Generic.List[string]
foreach($ln in ($raw2 -split "`n", 0, 'SimpleMatch')){
  [void]$lines.Add($ln)
}

$idxLen  = -1
$idxSha  = -1
$idxRoot = -1

for($i = 0; $i -lt $lines.Count; $i++){
  $t = $lines[$i].Trim()
  if($t -eq '$expectedLen  = [int64](LenOf $man.source)'){ $idxLen = $i; continue }
  if($t -eq '$expectedSha  = [string](PropOf $man.source "sha256")'){ $idxSha = $i; continue }
  if($t -eq '$expectedRoot = [string]$man.roots.block_root'){ $idxRoot = $i; continue }
}

if($idxLen  -lt 0){ Die "EXPECTED_LEN_LINE_NOT_FOUND_V59" }
if($idxSha  -lt 0){ Die "EXPECTED_SHA_LINE_NOT_FOUND_V59" }
if($idxRoot -lt 0){ Die "EXPECTED_ROOT_LINE_NOT_FOUND_V59" }

$lines[$idxLen]  = '$expectedLen  = [int64](PropOf $man.source "total_bytes")'
$lines[$idxSha]  = '$expectedSha  = [string](PropOf $man.roots "semantic_root")'
$lines[$idxRoot] = '$expectedRoot = [string](PropOf $man.roots "block_root")'

$out = ($lines.ToArray() -join "`n")
Write-Utf8NoBomLf $Target $out
Parse-GateFile_Parser $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v59: tree-manifest entries fallback + expected contract fix)") -ForegroundColor Green
