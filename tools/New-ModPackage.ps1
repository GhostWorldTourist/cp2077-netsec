# New-ModPackage.ps1 -- build the archive a Nexus user downloads and a mod
# manager installs.
#
# The zip's internal layout IS the install instruction: every mod manager for
# this game unpacks relative to the game root, so r6\ and archive\ have to sit at
# the top of the zip with nothing wrapping them. A folder in the way is the
# single most common reason a correctly-built mod does nothing after install.
#
# Only what the game loads goes in. The source tree also carries docs/, world/
# (the authored sector JSON) and tools/, which belong in the repo and would be
# noise in somebody's game folder.

[CmdletBinding()]
param(
    # Not defaulted from $PSScriptRoot: that is empty in a param block on
    # PowerShell 5.1 under -File. Resolved in the body.
    [string] $Root,
    [string] $OutDir,
    [string] $Version
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }

if (-not $Version) {
    Push-Location $Root
    try { $Version = (git describe --tags --abbrev=0 2>$null) } catch { }
    Pop-Location
}
if (-not $Version) { $Version = '1.0.0' }
if (-not $OutDir)  { $OutDir  = Join-Path $Root 'build' }

$src = Join-Path $Root 'src'
foreach ($need in 'r6\scripts\NetSec', 'r6\tweaks\NetSec', 'archive\pc\mod') {
    if (-not (Test-Path -LiteralPath (Join-Path $src $need))) {
        throw "missing $need under $src - refusing to build a package that would install nothing"
    }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zip = Join-Path $OutDir ("NetSec-$Version.zip")
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }

# Compress from INSIDE src so r6\ and archive\ land at the root of the zip.
Compress-Archive -Path (Join-Path $src '*') -DestinationPath $zip

Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $tops = $z.Entries | ForEach-Object { ($_.FullName -split '/')[0] } | Sort-Object -Unique
    $bad  = @($tops | Where-Object { $_ -notin 'r6', 'archive' })
    if ($bad) { throw "zip root has $($bad -join ', ') - a manager would install this to the wrong place" }
    Write-Host ""
    Write-Host "built  $zip"
    Write-Host ("       {0} file(s), {1:N0} KB, roots: {2}" -f $z.Entries.Count, ((Get-Item $zip).Length/1KB), ($tops -join ', '))
} finally { $z.Dispose() }

Write-Host ""
Write-Host "Install with Vortex or MO2, or unzip into the game folder."
