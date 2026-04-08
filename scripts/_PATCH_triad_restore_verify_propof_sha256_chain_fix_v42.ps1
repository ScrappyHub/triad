param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
$dir = Split-Path -Parent $Path
if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$t = $Text.Replace("`r`n","`n").Replace("`r","`n")
if (-not $t.EndsWith("`n")) { $t += "`n" }
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateFile([string]$Path){
$raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
$null = [ScriptBlock]::Create($raw)
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)) { Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$BackupDir = Join-Path $ScriptsDir ("_backup_triad_restore_verify_v42_" + $ts)
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Write-Host ("backupdir: {0}" -f $BackupDir) -ForegroundColor DarkGray

$Target = Join-Path $ScriptsDir "triad_restore_verify_v1.ps1"
if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Die ("MISSING_TARGET: " + $Target) }
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir ((Split-Path -Leaf $Target) + ".pre_patch")) -Force

$txt = (Get-Content -Raw -LiteralPath $Target -Encoding UTF8).Replace("`r`n","`n").Replace("`r","`n")

# Idempotency
if ($txt -match '(?im)PATCH_PROPOF_SHA256_CHAIN_V42') {
Parse-GateFile $Target
Write-Host ("OK: v42 already present: " + $Target) -ForegroundColor Green
return
}

# Ensure PropOf exists (insert after Set-StrictMode -Version Latest)
if ($txt -notmatch '(?im)^\s*function\s+PropOf\s*\(') {
$m = [regex]::Match($txt, '(?im)^\s*Set-StrictMode\s+-Version\s+Latest\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
if (-not $m.Success) { Die "NO_SET_STRICTMODE_ANCHOR_FOUND_FOR_PROPOF_V42" }
$pos = $m.Index + $m.Length

$helper = @(
'',
'# PATCH_PROPOF_SHA256_CHAIN_V42',
'function PropOf([Parameter(Mandatory=$true)]$Obj,[Parameter(Mandatory=$true)][string]$Name){',
' try {',
' if ($null -eq $Obj) { return $null }',
' $p = $Obj.PSObject.Properties[$Name]',
' if ($null -eq $p) { return $null }',
' return $p.Value',
' } catch { return $null }',
'}',
''
) -join "`n"

$txt = $txt.Substring(0,$pos) + "`n" + $helper + $txt.Substring($pos)
} else {
# still tag file so idempotency marker exists even if helper already present
$txt = "# PATCH_PROPOF_SHA256_CHAIN_V42`n" + $txt
}

$before = $txt

# Rewrite ANY member-chain ending with .sha256/.Sha256 (including direct $x.sha256)
# $x.sha256 -> (PropOf $x "sha256")
# $x.y.sha256 -> (PropOf $x.y "sha256")
$txt = [regex]::Replace(
$txt,
'(?im)(\$(?:script:|global:|local:)?[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\.(sha256|Sha256)\b',
'(PropOf $1 "sha256")'
)

if ($txt -eq $before) { Die "PATCH_NO_CHANGE_V42: no `$.sha256 patterns found to rewrite (script drift?)" }

Write-Utf8NoBomLf $Target $txt
Parse-GateFile $Target
Write-Host ("FINAL_OK: patched " + $Target + " (v42 rewrote `$.sha256/`$.a.b.sha256 -> (PropOf ... ""sha256""))") -ForegroundColor Green
