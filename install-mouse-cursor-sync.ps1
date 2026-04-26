<#
.SYNOPSIS
Installs the cursor sync solution for the current user.

.DESCRIPTION
Copies the project files to %LocalAppData%, generates the mirrored cursor,
creates redundant per-user autostart entries, and starts the sync process.
#>

param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'MouseCursorButtonSync')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runValueName = 'MouseCursorButtonSync'
$cursorRegistryPath = 'HKCU:\Control Panel\Cursors'
$startupFolder = [Environment]::GetFolderPath('Startup')
$startupLauncherName = 'MouseCursorButtonSync.vbs'
$bundleFiles = @(
    'mirror-cursor.ps1'
    'restore-cursor.ps1'
    'mouse-cursor-button-sync.ps1'
    'install-mouse-cursor-sync.ps1'
    'uninstall-mouse-cursor-sync.ps1'
    'install.cmd'
    'uninstall.cmd'
)

function Get-OriginalCursorPath {
    param(
        [string]$CursorName,
        [string]$BackupFileName,
        [string]$MirroredFileName,
        [string]$FallbackPath
    )

    $backupPath = Join-Path $PSScriptRoot $BackupFileName
    if (Test-Path -LiteralPath $backupPath) {
        $path = (Get-Content -LiteralPath $backupPath -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    $currentCursor = (Get-ItemProperty -Path $cursorRegistryPath).$CursorName
    if (
        -not [string]::IsNullOrWhiteSpace($currentCursor) -and
        (Test-Path -LiteralPath $currentCursor) -and
        ([System.IO.Path]::GetFileName($currentCursor) -ne $MirroredFileName)
    ) {
        return $currentCursor
    }

    return $FallbackPath
}

function Stop-ExistingSyncProcesses {
    $running = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -match 'mouse-cursor-button-sync\.ps1' }

    foreach ($process in $running) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }

    return @($running).Count
}

function Write-StartupLauncher {
    param(
        [string]$StartupPath,
        [string]$SyncScriptPath
    )

    $quotedScriptPath = $SyncScriptPath.Replace('"', '""')
    $launcherContent = @(
        'Set shell = CreateObject("WScript.Shell")'
        "shell.Run ""powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """"$quotedScriptPath"""" "", 0, False"
    )

    Set-Content -LiteralPath $StartupPath -Value $launcherContent -Encoding ASCII
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

$originalArrowPath = Get-OriginalCursorPath -CursorName 'Arrow' -BackupFileName 'original-arrow-path.txt' -MirroredFileName 'cursor-arrow-right.cur' -FallbackPath (Join-Path $env:SystemRoot 'Cursors\aero_arrow.cur')
$originalHandPath = Get-OriginalCursorPath -CursorName 'Hand' -BackupFileName 'original-hand-path.txt' -MirroredFileName 'cursor-hand-right.cur' -FallbackPath (Join-Path $env:SystemRoot 'Cursors\aero_link.cur')

$installedArrowBackupPath = Join-Path $installDir 'original-arrow-path.txt'
$installedHandBackupPath = Join-Path $installDir 'original-hand-path.txt'
$installedHelpBackupPath = Join-Path $installDir 'original-help-path.txt'
$installedAppStartingBackupPath = Join-Path $installDir 'original-appstarting-path.txt'
$installedMirrorScriptPath = Join-Path $installDir 'mirror-cursor.ps1'
$installedMirroredArrowPath = Join-Path $installDir 'cursor-arrow-right.cur'
$installedMirroredHandPath = Join-Path $installDir 'cursor-hand-right.cur'
$installedMirroredHelpPath = Join-Path $installDir 'cursor-help-right.cur'
$installedMirroredAppStartingPath = Join-Path $installDir 'cursor-appstarting-right.ani'
$installedSyncScriptPath = Join-Path $installDir 'mouse-cursor-button-sync.ps1'
$startupLauncherPath = Join-Path $startupFolder $startupLauncherName

$originalHelpPath = Get-OriginalCursorPath -CursorName 'Help' -BackupFileName 'original-help-path.txt' -MirroredFileName 'cursor-help-right.cur' -FallbackPath (Join-Path $env:SystemRoot 'Cursors\aero_helpsel.cur')
$originalAppStartingPath = Get-OriginalCursorPath -CursorName 'AppStarting' -BackupFileName 'original-appstarting-path.txt' -MirroredFileName 'cursor-appstarting-right.ani' -FallbackPath (Join-Path $env:SystemRoot 'Cursors\aero_working.ani')

Set-Content -LiteralPath $installedArrowBackupPath -Value $originalArrowPath -Encoding ASCII
Set-Content -LiteralPath $installedHandBackupPath -Value $originalHandPath -Encoding ASCII
Set-Content -LiteralPath $installedHelpBackupPath -Value $originalHelpPath -Encoding ASCII
Set-Content -LiteralPath $installedAppStartingBackupPath -Value $originalAppStartingPath -Encoding ASCII
& $installedMirrorScriptPath -SourceCursor $originalArrowPath -OutputCursor $installedMirroredArrowPath | Out-Null
& $installedMirrorScriptPath -SourceCursor $originalHandPath -OutputCursor $installedMirroredHandPath | Out-Null
& $installedMirrorScriptPath -SourceCursor $originalHelpPath -OutputCursor $installedMirroredHelpPath | Out-Null
& $installedMirrorScriptPath -SourceCursor $originalAppStartingPath -OutputCursor $installedMirroredAppStartingPath | Out-Null

$stoppedProcesses = Stop-ExistingSyncProcesses

$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installedSyncScriptPath`""
New-ItemProperty -Path $runKeyPath -Name $runValueName -Value $command -PropertyType String -Force | Out-Null
Write-StartupLauncher -StartupPath $startupLauncherPath -SyncScriptPath $installedSyncScriptPath

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
    OriginalArrow = $originalArrowPath
    OriginalHand = $originalHandPath
    OriginalHelp = $originalHelpPath
    OriginalAppStarting = $originalAppStartingPath
    MirroredArrow = $installedMirroredArrowPath
    MirroredHand = $installedMirroredHandPath
    MirroredHelp = $installedMirroredHelpPath
    MirroredAppStarting = $installedMirroredAppStartingPath
    RunValueName = $runValueName
    Command = $command
    StartupLauncher = $startupLauncherPath
    StoppedProcesses = $stoppedProcesses
}
