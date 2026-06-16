<#
  nvmx installer. Does everything in one shot:
    1. copies the module to a stable local folder (no "downloaded" mark, survives
       deleting your Downloads folder)
    2. unblocks it
    3. relaxes execution policy ONLY if it would otherwise block (CurrentUser,
       no admin, RemoteSigned = the safe default)
    4. wires it into your PowerShell profile (idempotent)

  Easiest: double-click install.cmd. Or:
    powershell -ExecutionPolicy Bypass -File .\Install.ps1
#>

[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'Nvmx.psm1'
if (-not (Test-Path -LiteralPath $src)) {
    throw "Nvmx.psm1 not found next to this installer ($PSScriptRoot)."
}

# 1) stable per-user location
$dest = Join-Path $env:LOCALAPPDATA 'nvmx'
New-Item -ItemType Directory -Path $dest -Force | Out-Null
$destModule = Join-Path $dest 'Nvmx.psm1'
Copy-Item -LiteralPath $src -Destination $destModule -Force

# 2) strip the mark-of-the-web so it counts as a trusted local file
Unblock-File -LiteralPath $destModule -ErrorAction SilentlyContinue

# 3) fix execution policy only if it currently blocks unsigned scripts
$eff = Get-ExecutionPolicy
if ($eff -eq 'Restricted' -or $eff -eq 'AllSigned') {
    Write-Host "Execution policy is '$eff' (blocks unsigned scripts)."
    Write-Host "Setting CurrentUser policy to RemoteSigned (safe default, your account only)."
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
}

# 4) wire into the profile (replace any old block so the path is always current)
$profilePath = $PROFILE
$profileDir  = Split-Path -Parent $profilePath
if (-not (Test-Path -LiteralPath $profileDir))  { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
if (-not (Test-Path -LiteralPath $profilePath)) { New-Item -ItemType File -Path $profilePath -Force | Out-Null }

$marker    = '# >>> nvmx >>>'
$endMarker = '# <<< nvmx <<<'
$content   = Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue
if (-not $content) { $content = '' }
if ($content -match [regex]::Escape($marker)) {
    $content = [regex]::Replace($content, '(?ms)\r?\n?# >>> nvmx >>>.*?# <<< nvmx <<<\r?\n?', "`r`n")
}
$block = "`r`n$marker`r`nImport-Module -Name `"$destModule`" -DisableNameChecking -Force`r`n$endMarker`r`n"
Set-Content -LiteralPath $profilePath -Value ($content.TrimEnd() + $block) -NoNewline

Write-Host ''
Write-Host "nvmx installed to: $destModule"
Write-Host 'Open a NEW terminal, then run:  nvmx-status'
Write-Host 'To remove later:  Uninstall-Nvmx   (or double-click uninstall.cmd)'
