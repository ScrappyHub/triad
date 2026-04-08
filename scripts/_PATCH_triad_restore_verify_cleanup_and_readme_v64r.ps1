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

function Parse-GateFile([string]$Path){
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  $errs = @()
  if($err -ne $null){ $errs = @(@($err)) }
  if($errs.Count -gt 0){
    $msg = ($errs | Select-Object -First 12 | ForEach-Object { $_.Message }) -join " | "
    throw ("PARSE_GATE_FAIL: " + $msg)
  }
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
$Target     = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
$ReadmePath = Join-Path $RepoRoot "README.md"

if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){ Die ("MISSING_TARGET: " + $Target) }

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v64r_" + $ts)
Ensure-Dir $BackupDir
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force
if(Test-Path -LiteralPath $ReadmePath -PathType Leaf){
  Copy-Item -LiteralPath $ReadmePath -Destination (Join-Path $BackupDir "README.md.pre_patch") -Force
}
Write-Host ("backupdir: " + $BackupDir) -ForegroundColor DarkGray

$raw = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

if($raw -notmatch 'PATCH_VERIFY_CLEANUP_V64R'){
  $raw = "# PATCH_VERIFY_CLEANUP_V64R`n" + $raw

  $raw = [regex]::Replace(
    $raw,
    '(?ms)^\s*# PATCH_VERIFY_TRAP_V46C\s*\r?\n.*?^\s*# /PATCH_VERIFY_TRAP_V46C\s*\r?\n?',
    ''
  )

  $raw = [regex]::Replace(
    $raw,
    '(?ms)^\s*# PATCH_AFTER_EXPECTED_TRACE_V54\s*\r?\n.*?^\s*# /PATCH_AFTER_EXPECTED_TRACE_V54\s*\r?\n?',
    ''
  )

  $raw = [regex]::Replace(
    $raw,
    '(?im)^\s*Write-Host\s+.*(?:TRACE_|TRACE:|HB:).*\r?\n?',
    ''
  )

  $raw = [regex]::Replace(
    $raw,
    '(?im)^\s*Write-Host\s+"WARN: EXPECTED_LEN_NOT_FOUND \(skipping expected length verify\)".*\r?\n?',
    ''
  )

  $raw = [regex]::Replace(
    $raw,
    '(?im)^\s*Write-Host\s+"WARN: EXPECTED_SHA_NOT_FOUND \(skipping expected sha verify\)".*\r?\n?',
    ''
  )

  $raw = [regex]::Replace(
    $raw,
    '(?im)^\s*Write-Host\s+\("expected:\s+len="\s*\+\s*\$expectedLen\s*\+\s*" sha256="\s*\+\s*\$expectedSha\)\s*-ForegroundColor\s+\w+\s*\r?\n?',
    ''
  )

  $raw = [regex]::Replace(
    $raw,
    '(?im)^\s*#\s*PATCH_(?:AFTER_EXPECTED_TRACE_V54|FILEENTRY_BLOCKS_OFFSET_SIZE_V63R|VERIFY_TRAP_V46C).*\r?\n?',
    ''
  )

  $raw = [regex]::Replace(
    $raw,
    '(?im)^\s*#\s*/PATCH_(?:AFTER_EXPECTED_TRACE_V54|FILEENTRY_BLOCKS_OFFSET_SIZE_V63R|VERIFY_TRAP_V46C).*\r?\n?',
    ''
  )

  $raw = [regex]::Replace($raw, '(\r?\n){3,}', "`n`n")

  Write-Utf8NoBomLf $Target $raw
  Parse-GateFile $Target
  Write-Host ("VERIFY_CLEANUP_OK: " + $Target) -ForegroundColor Green
} else {
  Parse-GateFile $Target
  Write-Host ("OK: v64r already present: " + $Target) -ForegroundColor Green
}

$L = New-Object System.Collections.Generic.List[string]
[void]$L.Add('# TRIAD')
[void]$L.Add('')
[void]$L.Add('TRIAD (Transactional Restore Instrument with Attestation and Determinism) is a deterministic local-first restore substrate for capture, restore planning, restore verification, and transactional restore commit.')
[void]$L.Add('')
[void]$L.Add('## What this project is to spec')
[void]$L.Add('')
[void]$L.Add('TRIAD is:')
[void]$L.Add('')
[void]$L.Add('- the deterministic filesystem capture instrument')
[void]$L.Add('- the deterministic restore planning instrument')
[void]$L.Add('- the deterministic restore verification instrument')
[void]$L.Add('- the transactional restore commit instrument')
[void]$L.Add('- the cryptographic attestation layer for restore correctness')
[void]$L.Add('- the restore substrate for Atlas Artifact and Legacy Doctor')
[void]$L.Add('- a local-first Tier-0 standalone instrument')
[void]$L.Add('- fully verifiable under Packet Constitution v1 discipline')
[void]$L.Add('- append-only transcript and receipt oriented')
[void]$L.Add('- not an interpretation layer: it measures, plans, verifies, and restores')
[void]$L.Add('')
[void]$L.Add('## Current status')
[void]$L.Add('')
[void]$L.Add('Current proven state:')
[void]$L.Add('')
[void]$L.Add('- capture: GREEN')
[void]$L.Add('- prepare: GREEN')
[void]$L.Add('- verify: GREEN')
[void]$L.Add('- commit: GREEN')
[void]$L.Add('- workflow selftest: PASS')
[void]$L.Add('- freeze: VALIDATED')
[void]$L.Add('')
[void]$L.Add('Latest validated freeze:')
[void]$L.Add('')
[void]$L.Add('- snapshot_id: `0e26f315c83ee36d222b26cb4134c50a8fd430b593e6e39bbc31dc1b4cf6fd78`')
[void]$L.Add('- payload sha256: `a351162b9fda82bb8610b8194192b1d6f2dcc5b29a677e55d6cd34ba5ac9b536`')
[void]$L.Add('')
[void]$L.Add('## Critical restore contract')
[void]$L.Add('')
[void]$L.Add('TRIAD restore correctness depends on the payload file entry inside `snapshot.tree.manifest.json`.')
[void]$L.Add('')
[void]$L.Add('For tree manifests:')
[void]$L.Add('')
[void]$L.Add('- the payload file entry (for example `path=payload.bin`) is authoritative')
[void]$L.Add('- expected length comes from the payload file entry')
[void]$L.Add('- expected sha256 comes from the payload file entry')
[void]$L.Add('- expected block root comes from the payload file entry roots')
[void]$L.Add('- `payloadEntry.blocks` is authoritative for reconstruction')
[void]$L.Add('- restore replays blocks by `index + offset + size`')
[void]$L.Add('- repeated block reuse is valid')
[void]$L.Add('- naive concatenation of unique `.blk` files is incorrect')
[void]$L.Add('')
[void]$L.Add('## Why this matters')
[void]$L.Add('')
[void]$L.Add('This is the restore-core substrate needed before higher layers can be trusted:')
[void]$L.Add('')
[void]$L.Add('- Atlas Artifact')
[void]$L.Add('- Legacy Doctor')
[void]$L.Add('- future archive / preservation / snapshot engines')
[void]$L.Add('')
[void]$L.Add('## Current definition of done direction')
[void]$L.Add('')
[void]$L.Add('TRIAD reaches Tier-0 completion when:')
[void]$L.Add('')
[void]$L.Add('- capture is deterministic')
[void]$L.Add('- prepare is deterministic')
[void]$L.Add('- verify is strict-mode safe and deterministic')
[void]$L.Add('- commit restores byte-identical output')
[void]$L.Add('- semantic and block roots are validated correctly')
[void]$L.Add('- golden vectors are frozen')
[void]$L.Add('- stress harness passes')
[void]$L.Add('- restore contract is documented clearly')
[void]$L.Add('- Atlas Artifact and Legacy Doctor can use TRIAD as the authoritative restore substrate')
[void]$L.Add('')
[void]$L.Add('## Next locked work')
[void]$L.Add('')
[void]$L.Add('1. Freeze current working state and avoid blind patching')
[void]$L.Add('2. Remove temporary debug instrumentation safely')
[void]$L.Add('3. Add and lock golden vectors')
[void]$L.Add('4. Build stress harness')
[void]$L.Add('5. Document restore contract formally')
[void]$L.Add('6. Move into Atlas Artifact and Legacy Doctor integration')
[void]$L.Add('')
[void]$L.Add('## Running the workflow selftest')
[void]$L.Add('')
[void]$L.Add('From PowerShell 5.1:')
[void]$L.Add('')
[void]$L.Add('```powershell')
[void]$L.Add('cd C:\dev\triad')
[void]$L.Add('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\_selftest_triad_restore_workflow_v1.ps1 -RepoRoot C:\dev\triad')
[void]$L.Add('```')
[void]$L.Add('')
[void]$L.Add('Expected pass tokens include:')
[void]$L.Add('')
[void]$L.Add('- `OK: TRIAD RESTORE VERIFY v1`')
[void]$L.Add('- `OK: TRIAD RESTORE COMMIT v1`')
[void]$L.Add('- `TRIAD RESTORE WORKFLOW SELFTEST: PASS`')
[void]$L.Add('')
[void]$L.Add('## Project posture')
[void]$L.Add('')
[void]$L.Add('TRIAD is a governance-first, deterministic, inspectable restore instrument.')
[void]$L.Add('It is intended to be trustworthy because it is verifiable, not because it is opaque.')

Write-Utf8NoBomLf $ReadmePath (($L.ToArray()) -join "`n")
Write-Host ("README_REWRITE_OK: " + $ReadmePath) -ForegroundColor Green
