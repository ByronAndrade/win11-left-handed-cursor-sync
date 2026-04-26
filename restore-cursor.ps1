<#
.SYNOPSIS
Restores the original Arrow, Hand, Help, and AppStarting cursors saved during installation.
#>

param(
    [string]$ArrowBackupPath = (Join-Path $PSScriptRoot 'original-arrow-path.txt'),
    [string]$HandBackupPath = (Join-Path $PSScriptRoot 'original-hand-path.txt'),
    [string]$HelpBackupPath = (Join-Path $PSScriptRoot 'original-help-path.txt'),
    [string]$AppStartingBackupPath = (Join-Path $PSScriptRoot 'original-appstarting-path.txt')
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

foreach ($cursorInfo in @(
    @{ Name = 'Hand'; BackupPath = $HandBackupPath },
    @{ Name = 'Help'; BackupPath = $HelpBackupPath },
    @{ Name = 'AppStarting'; BackupPath = $AppStartingBackupPath }
)) {
    if (Test-Path -LiteralPath $cursorInfo.BackupPath) {
        $originalValue = (Get-Content -LiteralPath $cursorInfo.BackupPath -Raw).Trim()
        if ([string]::IsNullOrWhiteSpace($originalValue)) {
            throw "The $($cursorInfo.Name) backup file is empty."
        }

        Set-Variable -Name "original$($cursorInfo.Name)" -Value $originalValue -Scope Script
    }
}

Set-ItemProperty -Path 'HKCU:\Control Panel\Cursors' -Name Arrow -Value $originalArrow
foreach ($cursorName in 'Hand', 'Help', 'AppStarting') {
    $variableName = "original$cursorName"
    if (Get-Variable -Name $variableName -Scope Script -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path 'HKCU:\Control Panel\Cursors' -Name $cursorName -Value (Get-Variable -Name $variableName -Scope Script).Value
    }
}

Reload-Cursors

[PSCustomObject]@{
    RestoredArrow = $originalArrow
    RestoredHand = (Get-Variable -Name 'originalHand' -Scope Script -ErrorAction SilentlyContinue).Value
    RestoredHelp = (Get-Variable -Name 'originalHelp' -Scope Script -ErrorAction SilentlyContinue).Value
    RestoredAppStarting = (Get-Variable -Name 'originalAppStarting' -Scope Script -ErrorAction SilentlyContinue).Value
    ArrowBackupPath = $ArrowBackupPath
    HandBackupPath = $HandBackupPath
    HelpBackupPath = $HelpBackupPath
    AppStartingBackupPath = $AppStartingBackupPath
}
