<#
  nvmx  -  nvm extended.

  Makes .nvmrc behave on Windows. Instead of `nvm use` (which on nvm-windows
  flips ONE global symlink shared by every terminal), nvmx wraps node/npm/npx
  so each command:
     1. searches the current dir + parents for a .nvmrc
     2. if found, runs the matching INSTALLED Node version directly
     3. if not found / not installed / nvm missing, uses your default Node
  The override lasts only for that one command. Nothing global changes.
#>

# --- discovery (these read the .nvmrc file, hence the Nvmrc names) ---------

function Find-NvmrcFile {
    [CmdletBinding()]
    param([string]$StartDir = (Get-Location).Path)

    $dir = $StartDir
    while ($true) {
        $candidate = Join-Path $dir '.nvmrc'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        $parent = Split-Path -Parent $dir
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Get-NvmrcVersion {
    [CmdletBinding()]
    param([string]$StartDir = (Get-Location).Path)

    $file = Find-NvmrcFile -StartDir $StartDir
    if (-not $file) { return $null }

    $raw = (Get-Content -LiteralPath $file -Raw)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    $line = ($raw -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
    if ($line) { return $line.Trim() }
    return $null
}

# --- nvm-windows detection -------------------------------------------------

function Test-NvmInstalled {
    [CmdletBinding()]
    param()
    if (-not $env:NVM_HOME) { return $false }
    if (-not (Test-Path -LiteralPath $env:NVM_HOME)) { return $false }
    return $true
}

# --- version resolution against nvm-windows installs -----------------------

function Resolve-NodeBinDir {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Version)

    if (-not (Test-NvmInstalled)) { return $null }
    $root = $env:NVM_HOME

    $req = $Version.Trim() -replace '^[vV]', ''

    if ($req -notmatch '^\d') {
        return [pscustomobject]@{ Unsupported = $true; Requested = $Version }
    }

    $installed = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'node.exe') } |
        ForEach-Object { $_.Name -replace '^[vV]', '' }

    if (-not $installed) { return $null }

    $match = $installed | Where-Object { $_ -eq $req } | Select-Object -First 1
    if (-not $match) {
        $candidates = $installed | Where-Object { $_ -eq $req -or $_ -like "$req.*" }
        if ($candidates) {
            $match = $candidates |
                Sort-Object { try { [version]$_ } catch { [version]'0.0.0' } } |
                Select-Object -Last 1
        }
    }

    if (-not $match) { return $null }
    return (Join-Path $root ("v$match"))
}

function Get-DefaultNodeExe {
    [CmdletBinding()]
    param()
    $cmd = Get-Command -Name node.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $cmd) {
        $cmd = Get-Command -Name node -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-NvmxNodeBinDir {
    <# Returns: BinDir, Source ('nvmrc'|'default'), Version. $null if no Node at all. #>
    [CmdletBinding()]
    param()

    $version = Get-NvmrcVersion
    if ($version) {
        if (-not (Test-NvmInstalled)) {
            Write-Warning "nvmx: .nvmrc asks for Node '$version', but nvm-windows isn't installed (NVM_HOME is not set). Install it from https://github.com/coreybutler/nvm-windows then run 'nvm install $version'. Using default Node for now."
        }
        else {
            $resolved = Resolve-NodeBinDir -Version $version
            if ($resolved -is [string] -and $resolved) {
                return [pscustomobject]@{ BinDir = $resolved; Source = 'nvmrc'; Version = $version }
            }
            elseif ($resolved -and $resolved.PSObject.Properties.Name -contains 'Unsupported') {
                Write-Warning "nvmx: .nvmrc version '$version' isn't a plain numeric version (e.g. lts/*). Using default Node."
            }
            else {
                Write-Warning "nvmx: Node '$version' (from .nvmrc) isn't installed. Run 'nvm install $version'. Using default Node for now."
            }
        }
    }

    $def = Get-DefaultNodeExe
    if (-not $def) {
        Write-Error "nvmx: no Node found on PATH. Install Node, or nvm-windows + 'nvm install <version>'."
        return $null
    }
    return [pscustomobject]@{ BinDir = (Split-Path -Parent $def); Source = 'default'; Version = $null }
}

# --- scoped execution ------------------------------------------------------

function Invoke-ScopedNodeTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BinDir,
        [Parameter(Mandatory)][ValidateSet('node','npm','npx')][string]$Tool,
        [Parameter()][string[]]$Arguments = @()
    )

    $exe = $null
    foreach ($ext in @('.exe', '.cmd', '.bat', '')) {
        $p = Join-Path $BinDir ($Tool + $ext)
        if (Test-Path -LiteralPath $p -PathType Leaf) { $exe = $p; break }
    }
    if (-not $exe) {
        Write-Error "nvmx: couldn't find '$Tool' in $BinDir"
        return
    }

    $oldPath = $env:PATH
    try {
        $env:PATH = "$BinDir;$oldPath"
        & $exe @Arguments
        $script:__nvmx_exit = $LASTEXITCODE
    }
    finally {
        $env:PATH = $oldPath
    }
    if ($null -ne $script:__nvmx_exit) { $global:LASTEXITCODE = $script:__nvmx_exit }
}

# --- the wrappers users actually call --------------------------------------

function node {
    $b = Get-NvmxNodeBinDir
    if (-not $b) { return }
    Invoke-ScopedNodeTool -BinDir $b.BinDir -Tool 'node' -Arguments $args
}

function npm {
    $b = Get-NvmxNodeBinDir
    if (-not $b) { return }
    Invoke-ScopedNodeTool -BinDir $b.BinDir -Tool 'npm' -Arguments $args
}

function npx {
    $b = Get-NvmxNodeBinDir
    if (-not $b) { return }
    Invoke-ScopedNodeTool -BinDir $b.BinDir -Tool 'npx' -Arguments $args
}

# --- diagnostics -----------------------------------------------------------

function Get-NvmxStatus {
    [CmdletBinding()]
    param()

    $file    = Find-NvmrcFile
    $version = Get-NvmrcVersion
    $b       = Get-NvmxNodeBinDir

    Write-Host ''
    if ($file) { Write-Host (".nvmrc : {0}  ->  '{1}'" -f $file, $version) }
    else       { Write-Host '.nvmrc : none in this folder or any parent' }

    if (-not (Test-NvmInstalled)) { Write-Host 'nvm    : not installed (NVM_HOME not set)' }
    else                          { Write-Host ("nvm    : {0}" -f $env:NVM_HOME) }

    if ($b) {
        $nodeExe = Join-Path $b.BinDir 'node.exe'
        $actual  = if (Test-Path -LiteralPath $nodeExe) { (& $nodeExe --version) 2>$null } else { '?' }
        Write-Host ("node   : {0}  [{1}]" -f $actual, $b.Source)
        Write-Host ("path   : {0}" -f $b.BinDir)
    }
    else {
        Write-Host 'node   : (none found)'
    }
    Write-Host ''
}

# --- uninstall (run this from any terminal) --------------------------------

function Uninstall-Nvmx {
    [CmdletBinding()]
    param()

    $profilePath = $PROFILE
    if ($profilePath -and (Test-Path -LiteralPath $profilePath)) {
        $c = Get-Content -LiteralPath $profilePath -Raw
        if ($c -match '# >>> nvmx >>>') {
            $clean = [regex]::Replace($c, '(?ms)\r?\n?# >>> nvmx >>>.*?# <<< nvmx <<<\r?\n?', "`r`n")
            Set-Content -LiteralPath $profilePath -Value $clean.TrimEnd() -NoNewline
            Write-Host "Removed nvmx from $profilePath"
        }
    }

    $dest = Join-Path $env:LOCALAPPDATA 'nvmx'
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Removed $dest"
    }

    Write-Host "nvmx uninstalled. The node/npm/npx wrappers stay active in THIS terminal until you open a new one."
}

Set-Alias -Name nvmx-status -Value Get-NvmxStatus

Export-ModuleMember -Function node, npm, npx, Get-NvmxStatus, Get-NvmrcVersion, Find-NvmrcFile, Test-NvmInstalled, Uninstall-Nvmx -Alias nvmx-status
