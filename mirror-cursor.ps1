<#
.SYNOPSIS
Generates a horizontally mirrored mouse cursor from an existing .cur file.

.DESCRIPTION
Mirrors every cursor size embedded in the source file and preserves the
correct hotspot for each size. With -Apply, it also updates the current
user's Arrow cursor and asks Windows to reload the cursor set immediately.
#>

param(
    [string]$SourceCursor = (Get-ItemProperty -Path 'HKCU:\Control Panel\Cursors').Arrow,
    [string]$OutputCursor = (Join-Path $PSScriptRoot 'cursor-arrow-right.cur'),
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-UInt16LE {
    param(
        [byte[]]$Buffer,
        [int]$Offset,
        [uint16]$Value
    )

    $valueBytes = [BitConverter]::GetBytes($Value)
    $Buffer[$Offset] = $valueBytes[0]
    $Buffer[$Offset + 1] = $valueBytes[1]
}

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

function Mirror-CursorFile {
    param(
        [string]$InputPath,
        [string]$OutputPath
    )

    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Source cursor not found: $InputPath"
    }

    $bytes = [System.IO.File]::ReadAllBytes($InputPath)
    $reserved = [BitConverter]::ToUInt16($bytes, 0)
    $type = [BitConverter]::ToUInt16($bytes, 2)
    $count = [BitConverter]::ToUInt16($bytes, 4)

    if ($reserved -ne 0 -or $type -ne 2) {
        throw "The file is not in the expected .cur format."
    }

    $mirrored = [byte[]]::new($bytes.Length)
    [Array]::Copy($bytes, $mirrored, $bytes.Length)

    for ($i = 0; $i -lt $count; $i++) {
        $entryOffset = 6 + (16 * $i)
        $imageOffset = [BitConverter]::ToUInt32($bytes, $entryOffset + 12)
        $imageSize = [BitConverter]::ToUInt32($bytes, $entryOffset + 8)

        $headerSize = [BitConverter]::ToUInt32($bytes, $imageOffset)
        $bitmapWidth = [BitConverter]::ToInt32($bytes, $imageOffset + 4)
        $bitmapHeight = [BitConverter]::ToInt32($bytes, $imageOffset + 8)
        $bitCount = [BitConverter]::ToUInt16($bytes, $imageOffset + 14)
        $compression = [BitConverter]::ToUInt32($bytes, $imageOffset + 16)
        $hotspotX = [BitConverter]::ToUInt16($bytes, $entryOffset + 4)

        if ($headerSize -lt 40) {
            throw "Unsupported DIB header in cursor image index $i."
        }

        if ($bitCount -ne 32 -or $compression -ne 0) {
            throw "Unsupported cursor format in image index $i (${bitCount}bpp, compression $compression)."
        }

        $width = [int][Math]::Abs($bitmapWidth)
        $height = [int]([Math]::Abs($bitmapHeight) / 2)
        $xorRowBytes = $width * 4
        $xorSize = $xorRowBytes * $height
        $maskRowBytes = [int]([Math]::Ceiling($width / 32.0) * 4)
        $maskSize = $maskRowBytes * $height

        $pixelStart = $imageOffset + $headerSize
        $maskStart = $pixelStart + $xorSize
        $imageEnd = $imageOffset + $imageSize

        if (($maskStart + $maskSize) -gt $imageEnd) {
            throw "Cursor data for image index $i appears to be truncated."
        }

        # Mirror the 32-bit pixel data row by row.
        $pixelRow = [byte[]]::new($xorRowBytes)
        for ($row = 0; $row -lt $height; $row++) {
            $rowOffset = $pixelStart + ($row * $xorRowBytes)
            [Array]::Copy($bytes, $rowOffset, $pixelRow, 0, $xorRowBytes)

            for ($x = 0; $x -lt $width; $x++) {
                $src = $x * 4
                $dst = ($width - 1 - $x) * 4
                [Array]::Copy($pixelRow, $src, $mirrored, $rowOffset + $dst, 4)
            }
        }

        # Mirror the 1-bit transparency mask separately.
        $maskRow = [byte[]]::new($maskRowBytes)
        $flippedMaskRow = [byte[]]::new($maskRowBytes)
        for ($row = 0; $row -lt $height; $row++) {
            $rowOffset = $maskStart + ($row * $maskRowBytes)
            [Array]::Copy($bytes, $rowOffset, $maskRow, 0, $maskRowBytes)
            [Array]::Clear($flippedMaskRow, 0, $maskRowBytes)

            for ($x = 0; $x -lt $width; $x++) {
                $srcByte = [int][Math]::Floor($x / 8.0)
                $srcBit = 7 - ($x % 8)
                $bitSet = (($maskRow[$srcByte] -shr $srcBit) -band 1) -eq 1

                if ($bitSet) {
                    $dstX = $width - 1 - $x
                    $dstByte = [int][Math]::Floor($dstX / 8.0)
                    $dstBit = 7 - ($dstX % 8)
                    $flippedMaskRow[$dstByte] = $flippedMaskRow[$dstByte] -bor [byte](1 -shl $dstBit)
                }
            }

            [Array]::Copy($flippedMaskRow, 0, $mirrored, $rowOffset, $maskRowBytes)
        }

        $newHotspotX = [uint16]($width - 1 - $hotspotX)
        Set-UInt16LE -Buffer $mirrored -Offset ($entryOffset + 4) -Value $newHotspotX
    }

    $outputDirectory = [System.IO.Path]::GetDirectoryName($OutputPath)
    if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
        throw "Could not determine the output directory."
    }

    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
    [System.IO.File]::WriteAllBytes($OutputPath, $mirrored)
}

$backupPath = Join-Path $PSScriptRoot 'original-arrow-path.txt'
if ($SourceCursor -eq $OutputCursor -and (Test-Path -LiteralPath $backupPath)) {
    $backedUpCursor = (Get-Content -LiteralPath $backupPath -Raw).Trim()
    if (-not [string]::IsNullOrWhiteSpace($backedUpCursor)) {
        $SourceCursor = $backedUpCursor
    }
}

Mirror-CursorFile -InputPath $SourceCursor -OutputPath $OutputCursor

if ($Apply) {
    $currentArrow = (Get-ItemProperty -Path 'HKCU:\Control Panel\Cursors').Arrow
    if ($currentArrow -ne $OutputCursor) {
        Set-Content -LiteralPath $backupPath -Value $currentArrow -Encoding ASCII
    }

    Set-ItemProperty -Path 'HKCU:\Control Panel\Cursors' -Name Arrow -Value $OutputCursor
    Reload-Cursors
}

[PSCustomObject]@{
    SourceCursor = $SourceCursor
    OutputCursor = $OutputCursor
    BackupPath = $backupPath
    Applied = [bool]$Apply
}
