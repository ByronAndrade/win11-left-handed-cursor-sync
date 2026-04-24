<#
.SYNOPSIS
Restores the original arrow cursor saved during installation.
#>

param(
    [string]$BackupPath = (Join-Path $PSScriptRoot 'original-arrow-path.txt')
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

if (-not (Test-Path -LiteralPath $BackupPath)) {
    throw "Backup file not found: $BackupPath"
}

$originalCursor = (Get-Content -LiteralPath $BackupPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($originalCursor)) {
    throw "The backup file is empty."
}

Set-ItemProperty -Path 'HKCU:\Control Panel\Cursors' -Name Arrow -Value $originalCursor
Reload-Cursors

[PSCustomObject]@{
    RestoredCursor = $originalCursor
    BackupPath = $BackupPath
}
