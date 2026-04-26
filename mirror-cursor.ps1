<#
.SYNOPSIS
Generates a horizontally mirrored mouse cursor from an existing .cur or .ani file.

.DESCRIPTION
Mirrors every cursor size embedded in the source file and preserves the
correct hotspot for each size. Animated .ani cursors are mirrored frame by
frame. With -Apply, it also updates the current user's Arrow cursor and asks
Windows to reload the cursor set immediately.
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

function Mirror-CurBytes {
    param(
        [byte[]]$Bytes
    )

    $reserved = [BitConverter]::ToUInt16($Bytes, 0)
    $type = [BitConverter]::ToUInt16($Bytes, 2)
    $count = [BitConverter]::ToUInt16($Bytes, 4)

    if ($reserved -ne 0 -or $type -ne 2) {
        throw "The file is not in the expected .cur format."
    }

    $mirrored = [byte[]]::new($Bytes.Length)
    [Array]::Copy($Bytes, $mirrored, $Bytes.Length)

    for ($i = 0; $i -lt $count; $i++) {
        $entryOffset = 6 + (16 * $i)
        $imageOffset = [BitConverter]::ToUInt32($Bytes, $entryOffset + 12)
        $imageSize = [BitConverter]::ToUInt32($Bytes, $entryOffset + 8)

        $headerSize = [BitConverter]::ToUInt32($Bytes, $imageOffset)
        $bitmapWidth = [BitConverter]::ToInt32($Bytes, $imageOffset + 4)
        $bitmapHeight = [BitConverter]::ToInt32($Bytes, $imageOffset + 8)
        $bitCount = [BitConverter]::ToUInt16($Bytes, $imageOffset + 14)
        $compression = [BitConverter]::ToUInt32($Bytes, $imageOffset + 16)
        $hotspotX = [BitConverter]::ToUInt16($Bytes, $entryOffset + 4)

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
            [Array]::Copy($Bytes, $rowOffset, $pixelRow, 0, $xorRowBytes)

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
            [Array]::Copy($Bytes, $rowOffset, $maskRow, 0, $maskRowBytes)
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

    return $mirrored
}

function Mirror-AniBytes {
    param(
        [byte[]]$Bytes
    )

    if ([Text.Encoding]::ASCII.GetString($Bytes, 0, 4) -ne 'RIFF' -or [Text.Encoding]::ASCII.GetString($Bytes, 8, 4) -ne 'ACON') {
        throw "The file is not in the expected .ani format."
    }

    $mirrored = [byte[]]::new($Bytes.Length)
    [Array]::Copy($Bytes, $mirrored, $Bytes.Length)

    for ($offset = 12; $offset -lt $Bytes.Length;) {
        $chunkId = [Text.Encoding]::ASCII.GetString($Bytes, $offset, 4)
        $chunkSize = [BitConverter]::ToUInt32($Bytes, $offset + 4)

        if ($chunkId -eq 'LIST' -and [Text.Encoding]::ASCII.GetString($Bytes, $offset + 8, 4) -eq 'fram') {
            $listEnd = $offset + 8 + $chunkSize
            for ($frameOffset = $offset + 12; $frameOffset -lt $listEnd;) {
                $frameId = [Text.Encoding]::ASCII.GetString($Bytes, $frameOffset, 4)
                $frameSize = [BitConverter]::ToUInt32($Bytes, $frameOffset + 4)

                if ($frameId -eq 'icon') {
                    $frameBytes = [byte[]]::new($frameSize)
                    [Array]::Copy($Bytes, $frameOffset + 8, $frameBytes, 0, $frameSize)
                    $mirroredFrame = Mirror-CurBytes -Bytes $frameBytes
                    [Array]::Copy($mirroredFrame, 0, $mirrored, $frameOffset + 8, $frameSize)
                }

                $frameOffset += 8 + $frameSize
                if (($frameOffset % 2) -eq 1) {
                    $frameOffset++
                }
            }
        }

        $offset += 8 + $chunkSize
        if (($offset % 2) -eq 1) {
            $offset++
        }
    }

    return $mirrored
}

function Mirror-CursorFile {
    param(
        [string]$InputPath,
        [string]$OutputPath
    )

    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Source cursor not found: $InputPath"
    }

    $inputBytes = [System.IO.File]::ReadAllBytes($InputPath)
    $extension = [System.IO.Path]::GetExtension($InputPath).ToLowerInvariant()
    switch ($extension) {
        '.cur' { $mirroredBytes = Mirror-CurBytes -Bytes $inputBytes }
        '.ani' { $mirroredBytes = Mirror-AniBytes -Bytes $inputBytes }
        default { throw "Unsupported cursor format: $extension" }
    }

    $outputDirectory = [System.IO.Path]::GetDirectoryName($OutputPath)
    if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
        throw "Could not determine the output directory."
    }

    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
    [System.IO.File]::WriteAllBytes($OutputPath, $mirroredBytes)
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
