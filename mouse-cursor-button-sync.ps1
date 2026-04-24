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
$script:BackupPath = Join-Path $PSScriptRoot 'original-arrow-path.txt'
$script:MirroredCursorPath = Join-Path $PSScriptRoot 'cursor-arrow-right.cur'
$script:MirrorScriptPath = Join-Path $PSScriptRoot 'mirror-cursor.ps1'

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

function Get-LeftCursorPath {
    if (-not (Test-Path -LiteralPath $script:BackupPath)) {
        throw "Original cursor backup not found at $($script:BackupPath)."
    }

    $path = (Get-Content -LiteralPath $script:BackupPath -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "The original cursor backup file is empty."
    }

    return $path
}

function Ensure-MirroredCursor {
    $leftCursor = Get-LeftCursorPath

    if (-not (Test-Path -LiteralPath $script:MirrorScriptPath)) {
        throw "Mirror script not found at $($script:MirrorScriptPath)."
    }

    $needsRefresh = -not (Test-Path -LiteralPath $script:MirroredCursorPath)
    if (-not $needsRefresh) {
        $leftTime = (Get-Item -LiteralPath $leftCursor).LastWriteTimeUtc
        $mirrorTime = (Get-Item -LiteralPath $script:MirroredCursorPath).LastWriteTimeUtc
        $needsRefresh = $mirrorTime -lt $leftTime
    }

    if ($needsRefresh) {
        & $script:MirrorScriptPath -SourceCursor $leftCursor -OutputCursor $script:MirroredCursorPath | Out-Null
    }

    return $script:MirroredCursorPath
}

function Get-DesiredCursorPath {
    $swapValue = (Get-ItemProperty -Path $script:MouseRegistryPath).SwapMouseButtons
    if ([string]$swapValue -eq '1') {
        return Ensure-MirroredCursor
    }

    return Get-LeftCursorPath
}

function Sync-Cursor {
    $desiredCursor = Get-DesiredCursorPath
    $currentCursor = (Get-ItemProperty -Path $script:CursorRegistryPath).Arrow

    if ($currentCursor -ne $desiredCursor) {
        Set-ItemProperty -Path $script:CursorRegistryPath -Name Arrow -Value $desiredCursor
        Reload-Cursors
    }

    return $desiredCursor
}

$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, $script:MutexName, [ref]$createdNew)
if (-not $createdNew) {
    $mutex.Dispose()
    return
}

try {
    if ($RunOnce) {
        Sync-Cursor | Out-Null
        return
    }

    while ($true) {
        Sync-Cursor | Out-Null
        Start-Sleep -Milliseconds $PollMilliseconds
    }
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
