<#
.SYNOPSIS
Restores the original Arrow and Hand cursors saved during installation.
#>

param(
    [string]$ArrowBackupPath = (Join-Path $PSScriptRoot 'original-arrow-path.txt'),
    [string]$HandBackupPath = (Join-Path $PSScriptRoot 'original-hand-path.txt')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

if (-not (Test-Path -LiteralPath $ArrowBackupPath)) {
    throw "Arrow backup file not found: $ArrowBackupPath"
}

$originalArrow = (Get-Content -LiteralPath $ArrowBackupPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($originalArrow)) {
    throw "The Arrow backup file is empty."
}

$handBackupAvailable = Test-Path -LiteralPath $HandBackupPath
$originalHand = $null
if ($handBackupAvailable) {
    $originalHand = (Get-Content -LiteralPath $HandBackupPath -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($originalHand)) {
        throw "The Hand backup file is empty."
    }
}

Set-ItemProperty -Path 'HKCU:\Control Panel\Cursors' -Name Arrow -Value $originalArrow
if ($handBackupAvailable) {
    Set-ItemProperty -Path 'HKCU:\Control Panel\Cursors' -Name Hand -Value $originalHand
}

Reload-Cursors

[PSCustomObject]@{
    RestoredArrow = $originalArrow
    RestoredHand = $originalHand
    ArrowBackupPath = $ArrowBackupPath
    HandBackupPath = $HandBackupPath
}
