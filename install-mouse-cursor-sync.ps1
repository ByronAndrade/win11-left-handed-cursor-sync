<#
.SYNOPSIS
Installs the cursor sync solution for the current user.

.DESCRIPTION
Copies the project files to %LocalAppData%, generates the mirrored cursor,
creates the per-user autostart entry, and starts the sync process.
#>

param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'MouseCursorButtonSync')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runValueName = 'MouseCursorButtonSync'
$cursorRegistryPath = 'HKCU:\Control Panel\Cursors'
$bundleFiles = @(
    'mirror-cursor.ps1'
    'restore-cursor.ps1'
    'mouse-cursor-button-sync.ps1'
    'install-mouse-cursor-sync.ps1'
    'uninstall-mouse-cursor-sync.ps1'
)

function Get-LeftCursorPath {
    $backupPath = Join-Path $PSScriptRoot 'original-arrow-path.txt'
    if (Test-Path -LiteralPath $backupPath) {
        $path = (Get-Content -LiteralPath $backupPath -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    $currentCursor = (Get-ItemProperty -Path $cursorRegistryPath).Arrow
    if (
        -not [string]::IsNullOrWhiteSpace($currentCursor) -and
        (Test-Path -LiteralPath $currentCursor) -and
        ([System.IO.Path]::GetFileName($currentCursor) -ne 'cursor-arrow-right.cur')
    ) {
        return $currentCursor
    }

    return (Join-Path $env:SystemRoot 'Cursors\aero_arrow.cur')
}

function Stop-ExistingSyncProcesses {
    $running = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -match 'mouse-cursor-button-sync\.ps1' }

    foreach ($process in $running) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }

    return @($running).Count
}

foreach ($file in $bundleFiles) {
    $sourcePath = Join-Path $PSScriptRoot $file
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Required file not found: $sourcePath"
    }
}

$installDir = [System.IO.Path]::GetFullPath($InstallDir)
[System.IO.Directory]::CreateDirectory($installDir) | Out-Null

foreach ($file in $bundleFiles) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $installDir $file) -Force
}

$leftCursor = Get-LeftCursorPath
$installedBackupPath = Join-Path $installDir 'original-arrow-path.txt'
$installedMirrorScriptPath = Join-Path $installDir 'mirror-cursor.ps1'
$installedMirroredCursorPath = Join-Path $installDir 'cursor-arrow-right.cur'
$installedSyncScriptPath = Join-Path $installDir 'mouse-cursor-button-sync.ps1'

Set-Content -LiteralPath $installedBackupPath -Value $leftCursor -Encoding ASCII
& $installedMirrorScriptPath -SourceCursor $leftCursor -OutputCursor $installedMirroredCursorPath | Out-Null

$stoppedProcesses = Stop-ExistingSyncProcesses

$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installedSyncScriptPath`""
New-ItemProperty -Path $runKeyPath -Name $runValueName -Value $command -PropertyType String -Force | Out-Null

& $installedSyncScriptPath -RunOnce | Out-Null
Start-Process -WindowStyle Hidden -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile'
    '-ExecutionPolicy', 'Bypass'
    '-WindowStyle', 'Hidden'
    '-File', $installedSyncScriptPath
)

[PSCustomObject]@{
    Installed = $true
    InstallDir = $installDir
    LeftCursor = $leftCursor
    MirroredCursor = $installedMirroredCursorPath
    RunValueName = $runValueName
    Command = $command
    StoppedProcesses = $stoppedProcesses
}
