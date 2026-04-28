<#
.SYNOPSIS
Removes autostart and stops the cursor sync watcher.
#>

param(
    [switch]$RestoreCursorForCurrentButton,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'MouseCursorButtonSync')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$managedRoot = [System.IO.Path]::GetFullPath($InstallDir)
$syncScriptPath = Join-Path $managedRoot 'mouse-cursor-button-sync.ps1'
$watcherScriptPath = Join-Path $managedRoot 'mouse-cursor-button-sync.vbs'
$startupLauncherPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'MouseCursorButtonSync.vbs'

$runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runValueName = 'MouseCursorButtonSync'
if (Get-ItemProperty -Path $runKeyPath -Name $runValueName -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $runKeyPath -Name $runValueName
}

if (Test-Path -LiteralPath $startupLauncherPath) {
    Remove-Item -LiteralPath $startupLauncherPath -Force
}

$running = Get-CimInstance Win32_Process |
    Where-Object {
        (
            $_.Name -eq 'powershell.exe' -and
            $_.CommandLine -match 'mouse-cursor-button-sync\.ps1'
        ) -or (
            $_.Name -eq 'wscript.exe' -and
            $_.CommandLine -match 'mouse-cursor-button-sync\.vbs'
        )
    }

foreach ($process in $running) {
    Stop-Process -Id $process.ProcessId -Force
}

if ($RestoreCursorForCurrentButton -and (Test-Path -LiteralPath $syncScriptPath)) {
    & $syncScriptPath -RunOnce
}

[PSCustomObject]@{
    Uninstalled = $true
    InstallDir = $managedRoot
    WatcherScript = $watcherScriptPath
    StartupLauncher = $startupLauncherPath
    StoppedProcesses = @($running).Count
}
