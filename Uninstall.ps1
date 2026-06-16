<#
  Removes nvmx: deletes the profile block and the installed module folder.
  Easiest: double-click uninstall.cmd. Or run Uninstall-Nvmx from any terminal.
#>
$ErrorActionPreference = 'Stop'

$profilePath = $PROFILE
if ($profilePath -and (Test-Path -LiteralPath $profilePath)) {
    $c = Get-Content -LiteralPath $profilePath -Raw
    if ($c -match '# >>> nvmx >>>') {
        $clean = [regex]::Replace($c, '(?ms)\r?\n?# >>> nvmx >>>.*?# <<< nvmx <<<\r?\n?', "`r`n")
        Set-Content -LiteralPath $profilePath -Value $clean.TrimEnd() -NoNewline
        Write-Host "Removed nvmx block from $profilePath"
    }
}

$dest = Join-Path $env:LOCALAPPDATA 'nvmx'
if (Test-Path -LiteralPath $dest) {
    Remove-Item -LiteralPath $dest -Recurse -Force
    Write-Host "Removed $dest"
}

Write-Host 'nvmx uninstalled. Open a new terminal.'
