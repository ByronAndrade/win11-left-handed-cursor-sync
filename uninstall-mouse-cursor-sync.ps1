<#
.SYNOPSIS
Removes autostart and stops the cursor sync background process.
#>

param(
    [switch]$RestoreCursorForCurrentButton,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'MouseCursorButtonSync')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runValueName = 'MouseCursorButtonSync'
$managedRoot = [System.IO.Path]::GetFullPath($InstallDir)
$syncScriptPath = Join-Path $managedRoot 'mouse-cursor-button-sync.ps1'

if (Get-ItemProperty -Path $runKeyPath -Name $runValueName -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $runKeyPath -Name $runValueName
}

$running = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -match 'mouse-cursor-button-sync\.ps1' }

foreach ($process in $running) {
    Stop-Process -Id $process.ProcessId -Force
}

if ($RestoreCursorForCurrentButton -and (Test-Path -LiteralPath $syncScriptPath)) {
    & $syncScriptPath -RunOnce
}

[PSCustomObject]@{
    Uninstalled = $true
    InstallDir = $managedRoot
    StoppedProcesses = @($running).Count
}
