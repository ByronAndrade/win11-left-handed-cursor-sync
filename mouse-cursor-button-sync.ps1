<#
.SYNOPSIS
Keeps the main Windows arrow cursor in sync with the primary mouse button.

.DESCRIPTION
When SwapMouseButtons is enabled, this script applies a mirrored cursor.
When the setting is disabled, it restores the original cursor path saved
during installation.
#>

param(
    [int]$PollMilliseconds = 750,
    [switch]$RunOnce
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:MutexName = 'Local\MouseCursorButtonSync'
$script:CursorRegistryPath = 'HKCU:\Control Panel\Cursors'
$script:MouseRegistryPath = 'HKCU:\Control Panel\Mouse'
$script:MirrorScriptPath = Join-Path $PSScriptRoot 'mirror-cursor.ps1'
$script:CursorSpecs = @(
    @{
        Name = 'Arrow'
        BackupPath = (Join-Path $PSScriptRoot 'original-arrow-path.txt')
        MirroredPath = (Join-Path $PSScriptRoot 'cursor-arrow-right.cur')
    }
    @{
        Name = 'Hand'
        BackupPath = (Join-Path $PSScriptRoot 'original-hand-path.txt')
        MirroredPath = (Join-Path $PSScriptRoot 'cursor-hand-right.cur')
    }
)

function Reload-Cursors {
    if (-not ('CursorNativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CursorNativeMethods
{
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool SystemParametersInfo(
        uint uiAction,
        uint uiParam,
        IntPtr pvParam,
        uint fWinIni
    );
}
'@
    }

    $spiSetCursors = 0x0057
    if (-not [CursorNativeMethods]::SystemParametersInfo($spiSetCursors, 0, [IntPtr]::Zero, 0)) {
        throw "Windows could not reload the cursor set."
    }
}

function Get-CursorSpec {
    param(
        [string]$CursorName
    )

    return $script:CursorSpecs | Where-Object { $_.Name -eq $CursorName } | Select-Object -First 1
}

function Get-OriginalCursorPath {
    param(
        [string]$CursorName
    )

    $cursorSpec = Get-CursorSpec -CursorName $CursorName
    if ($null -eq $cursorSpec) {
        throw "Cursor spec not found for $CursorName."
    }

    if (-not (Test-Path -LiteralPath $cursorSpec.BackupPath)) {
        throw "Original cursor backup not found at $($cursorSpec.BackupPath)."
    }

    $path = (Get-Content -LiteralPath $cursorSpec.BackupPath -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "The original cursor backup file is empty."
    }

    return $path
}

function Ensure-MirroredCursor {
    param(
        [string]$CursorName
    )

    $cursorSpec = Get-CursorSpec -CursorName $CursorName
    if ($null -eq $cursorSpec) {
        throw "Cursor spec not found for $CursorName."
    }

    $leftCursor = Get-OriginalCursorPath -CursorName $CursorName

    if (-not (Test-Path -LiteralPath $script:MirrorScriptPath)) {
        throw "Mirror script not found at $($script:MirrorScriptPath)."
    }

    $needsRefresh = -not (Test-Path -LiteralPath $cursorSpec.MirroredPath)
    if (-not $needsRefresh) {
        $leftTime = (Get-Item -LiteralPath $leftCursor).LastWriteTimeUtc
        $mirrorTime = (Get-Item -LiteralPath $cursorSpec.MirroredPath).LastWriteTimeUtc
        $needsRefresh = $mirrorTime -lt $leftTime
    }

    if ($needsRefresh) {
        & $script:MirrorScriptPath -SourceCursor $leftCursor -OutputCursor $cursorSpec.MirroredPath | Out-Null
    }

    return $cursorSpec.MirroredPath
}

function Get-DesiredCursorMap {
    $swapValue = (Get-ItemProperty -Path $script:MouseRegistryPath).SwapMouseButtons
    $useMirroredCursors = [string]$swapValue -eq '1'

    $desired = @{}
    foreach ($cursorSpec in $script:CursorSpecs) {
        if ($useMirroredCursors) {
            $desired[$cursorSpec.Name] = Ensure-MirroredCursor -CursorName $cursorSpec.Name
        }
        else {
            $desired[$cursorSpec.Name] = Get-OriginalCursorPath -CursorName $cursorSpec.Name
        }
    }

    return $desired
}

function Sync-Cursors {
    $desiredCursorMap = Get-DesiredCursorMap
    $currentCursorValues = Get-ItemProperty -Path $script:CursorRegistryPath
    $needsReload = $false

    foreach ($cursorSpec in $script:CursorSpecs) {
        $cursorName = $cursorSpec.Name
        $desiredCursor = $desiredCursorMap[$cursorName]
        $currentCursor = $currentCursorValues.$cursorName

        if ($currentCursor -ne $desiredCursor) {
            Set-ItemProperty -Path $script:CursorRegistryPath -Name $cursorName -Value $desiredCursor
            $needsReload = $true
        }
    }

    if ($needsReload) {
        Reload-Cursors
    }

    return $desiredCursorMap
}

$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, $script:MutexName, [ref]$createdNew)
if (-not $createdNew) {
    $mutex.Dispose()
    return
}

try {
    if ($RunOnce) {
        Sync-Cursors | Out-Null
        return
    }

    while ($true) {
        Sync-Cursors | Out-Null
        Start-Sleep -Milliseconds $PollMilliseconds
    }
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
