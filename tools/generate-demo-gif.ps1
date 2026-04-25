Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$outputDir = Join-Path $root 'docs'
$framesDir = Join-Path $root 'tmp-gif-frames'
$gifPath = Join-Path $outputDir 'demo.gif'
$palettePath = Join-Path $outputDir 'demo-palette.png'
$ffmpegPath = (Get-Command ffmpeg.exe -ErrorAction Stop).Source

Add-Type -AssemblyName System.Drawing

function New-Color {
    param(
        [int]$R,
        [int]$G,
        [int]$B,
        [int]$A = 255
    )

    return [System.Drawing.Color]::FromArgb($A, $R, $G, $B)
}

function Draw-RoundedRectangle {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Brush]$Brush,
        [System.Drawing.Pen]$Pen,
        [float]$X,
        [float]$Y,
        [float]$Width,
        [float]$Height,
        [float]$Radius
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $Radius * 2

    $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
    $path.AddArc($X + $Width - $diameter, $Y + $Height - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()

    $Graphics.FillPath($Brush, $path)
    if ($null -ne $Pen) {
        $Graphics.DrawPath($Pen, $path)
    }

    $path.Dispose()
}

function Draw-Cursor {
    param(
        [System.Drawing.Graphics]$Graphics,
        [float]$CenterX,
        [float]$CenterY,
        [float]$Scale,
        [bool]$PointRight
    )

    $points = @(
        [System.Drawing.PointF]::new(0.0, 0.0),
        [System.Drawing.PointF]::new(0.0, 52.0),
        [System.Drawing.PointF]::new(14.0, 39.5),
        [System.Drawing.PointF]::new(24.0, 62.0),
        [System.Drawing.PointF]::new(34.0, 57.0),
        [System.Drawing.PointF]::new(24.0, 35.0),
        [System.Drawing.PointF]::new(45.0, 35.0)
    )

    $transformed = foreach ($point in $points) {
        $x = $point.X
        if ($PointRight) {
            $x = 45.0 - $x
        }

        [System.Drawing.PointF]::new(
            $CenterX + (($x - 22.5) * $Scale),
            $CenterY + (($point.Y - 31.0) * $Scale)
        )
    }

    $shadowBrush = [System.Drawing.SolidBrush]::new((New-Color 0 0 0 55))
    $fillBrush = [System.Drawing.SolidBrush]::new((New-Color 255 255 255))
    $outlinePen = [System.Drawing.Pen]::new((New-Color 17 24 39), 5.0)
    $outlinePen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round

    $shadow = foreach ($point in $transformed) {
        [System.Drawing.PointF]::new($point.X + 8, $point.Y + 8)
    }

    $Graphics.FillPolygon($shadowBrush, $shadow)
    $Graphics.FillPolygon($fillBrush, $transformed)
    $Graphics.DrawPolygon($outlinePen, $transformed)

    $shadowBrush.Dispose()
    $fillBrush.Dispose()
    $outlinePen.Dispose()
}

function Draw-Text {
    param(
        [System.Drawing.Graphics]$Graphics,
        [string]$Text,
        [System.Drawing.Font]$Font,
        [System.Drawing.Brush]$Brush,
        [float]$X,
        [float]$Y
    )

    $Graphics.DrawString($Text, $Font, $Brush, $X, $Y)
}

if (Test-Path -LiteralPath $framesDir) {
    Remove-Item -LiteralPath $framesDir -Recurse -Force
}

[System.IO.Directory]::CreateDirectory($framesDir) | Out-Null
[System.IO.Directory]::CreateDirectory($outputDir) | Out-Null

$width = 1200
$height = 675
$fps = 12
$totalFrames = 36
$leftHoldFrames = 10
$transitionFrames = 8
$rightHoldFrames = 18

$fontFamily = 'Segoe UI'
$titleFont = New-Object System.Drawing.Font($fontFamily, 28, [System.Drawing.FontStyle]::Bold)
$bodyFont = New-Object System.Drawing.Font($fontFamily, 17, [System.Drawing.FontStyle]::Regular)
$smallFont = New-Object System.Drawing.Font($fontFamily, 15, [System.Drawing.FontStyle]::Regular)
$buttonFont = New-Object System.Drawing.Font($fontFamily, 18, [System.Drawing.FontStyle]::Bold)

$bgColor = New-Color 248 250 252
$textPrimary = [System.Drawing.SolidBrush]::new((New-Color 15 23 42))
$textMuted = [System.Drawing.SolidBrush]::new((New-Color 71 85 105))
$textLight = [System.Drawing.SolidBrush]::new((New-Color 255 255 255))
$cardBrush = [System.Drawing.SolidBrush]::new((New-Color 255 255 255))
$cardPen = [System.Drawing.Pen]::new((New-Color 226 232 240), 1.5)
$panelBrush = [System.Drawing.SolidBrush]::new((New-Color 241 245 249))
$pillTrackBrush = [System.Drawing.SolidBrush]::new((New-Color 226 232 240))
$leftPillBrush = [System.Drawing.SolidBrush]::new((New-Color 148 163 184))
$rightPillBrush = [System.Drawing.SolidBrush]::new((New-Color 14 165 233))
$shadowBrush = [System.Drawing.SolidBrush]::new((New-Color 15 23 42 18))

for ($frame = 0; $frame -lt $totalFrames; $frame++) {
    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.Clear($bgColor)

    $state = if ($frame -lt $leftHoldFrames) {
        0.0
    }
    elseif ($frame -lt ($leftHoldFrames + $transitionFrames)) {
        ($frame - $leftHoldFrames + 1) / $transitionFrames
    }
    else {
        1.0
    }

    $ease = $state * $state * (3 - (2 * $state))
    $rightSelected = $ease -ge 0.5

    Draw-Text -Graphics $graphics -Text 'Windows 11 left-handed cursor sync' -Font $titleFont -Brush $textPrimary -X 92 -Y 64
    Draw-Text -Graphics $graphics -Text 'The main cursor and link hand follow the Primary mouse button setting automatically.' -Font $bodyFont -Brush $textMuted -X 92 -Y 108

    $shadowY = 170
    Draw-RoundedRectangle -Graphics $graphics -Brush $shadowBrush -Pen $null -X 86 -Y ($shadowY + 10) -Width 1028 -Height 394 -Radius 28
    Draw-RoundedRectangle -Graphics $graphics -Brush $cardBrush -Pen $cardPen -X 86 -Y $shadowY -Width 1028 -Height 394 -Radius 28

    Draw-Text -Graphics $graphics -Text 'Primary mouse button' -Font $buttonFont -Brush $textPrimary -X 132 -Y 220
    Draw-Text -Graphics $graphics -Text 'When set to Right, the main cursor and link hand point right. When set back to Left, the default cursors return.' -Font $smallFont -Brush $textMuted -X 132 -Y 256

    $pillX = 770
    $pillY = 214
    $pillWidth = 260
    $pillHeight = 64
    Draw-RoundedRectangle -Graphics $graphics -Brush $pillTrackBrush -Pen $null -X $pillX -Y $pillY -Width $pillWidth -Height $pillHeight -Radius 24

    $half = ($pillWidth - 8) / 2
    $highlightX = $pillX + 4 + (($half - 4) * $ease)
    $highlightBrush = if ($ease -lt 0.5) { $leftPillBrush } else { $rightPillBrush }
    Draw-RoundedRectangle -Graphics $graphics -Brush $highlightBrush -Pen $null -X $highlightX -Y ($pillY + 4) -Width ($half) -Height ($pillHeight - 8) -Radius 20

    $leftTextBrush = if ($ease -lt 0.45) { $textLight } else { $textPrimary }
    $rightTextBrush = if ($ease -gt 0.55) { $textLight } else { $textPrimary }

    Draw-Text -Graphics $graphics -Text 'Left' -Font $buttonFont -Brush $leftTextBrush -X ($pillX + 44) -Y ($pillY + 17)
    Draw-Text -Graphics $graphics -Text 'Right' -Font $buttonFont -Brush $rightTextBrush -X ($pillX + 154) -Y ($pillY + 17)

    Draw-RoundedRectangle -Graphics $graphics -Brush $panelBrush -Pen $null -X 126 -Y 320 -Width 948 -Height 198 -Radius 24

    $cursorCenterX = 330 + (540 * $ease)
    Draw-Cursor -Graphics $graphics -CenterX $cursorCenterX -CenterY 420 -Scale 3.7 -PointRight:$rightSelected

    if ($rightSelected) {
        $cursorLabel = 'Right-facing mirrored arrow'
        $buttonLabel = 'Primary mouse button: Right'
    }
    else {
        $cursorLabel = 'Default left-facing arrow'
        $buttonLabel = 'Primary mouse button: Left'
    }

    Draw-Text -Graphics $graphics -Text 'Cursor direction' -Font $bodyFont -Brush $textPrimary -X 640 -Y 378
    Draw-Text -Graphics $graphics -Text $cursorLabel -Font $bodyFont -Brush $textMuted -X 640 -Y 414
    Draw-Text -Graphics $graphics -Text $buttonLabel -Font $bodyFont -Brush $textMuted -X 640 -Y 452

    Draw-Text -Graphics $graphics -Text 'Open-source fix for a small but real accessibility / ergonomics issue.' -Font $smallFont -Brush $textMuted -X 92 -Y 590
    Draw-Text -Graphics $graphics -Text 'Repository: win11-left-handed-cursor-sync' -Font $smallFont -Brush $textPrimary -X 92 -Y 620

    $framePath = Join-Path $framesDir ('frame-{0:D3}.png' -f $frame)
    $bitmap.Save($framePath, [System.Drawing.Imaging.ImageFormat]::Png)

    $graphics.Dispose()
    $bitmap.Dispose()
}

& $ffmpegPath -y -framerate $fps -i (Join-Path $framesDir 'frame-%03d.png') -vf "palettegen=reserve_transparent=0" -frames:v 1 -update 1 $palettePath | Out-Null
& $ffmpegPath -y -framerate $fps -i (Join-Path $framesDir 'frame-%03d.png') -i $palettePath -lavfi "paletteuse=dither=sierra2_4a" $gifPath | Out-Null

Remove-Item -LiteralPath $framesDir -Recurse -Force
Remove-Item -LiteralPath $palettePath -Force

[PSCustomObject]@{
    GifPath = $gifPath
    Frames = $totalFrames
    FPS = $fps
}
