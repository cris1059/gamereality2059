param(
    [string]$FontPath = "Modelos Personajes\blanka-free-for-commercial-use\blanka-free-for-commercial-use\Blanka.otf",
    [string]$OutputDirectory = "assets-source\ui"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$resolvedFont = (Resolve-Path -LiteralPath $FontPath).Path
$resolvedOutput = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputDirectory))
[System.IO.Directory]::CreateDirectory($resolvedOutput) | Out-Null

$characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,:;!?+-/%()[]<>_"
$columns = 8
$rows = 8
$cellSize = 192
$atlasSize = $columns * $cellSize

$fontCollection = [System.Drawing.Text.PrivateFontCollection]::new()
$fontCollection.AddFontFile($resolvedFont)
if ($fontCollection.Families.Count -eq 0) {
    throw "Blanka font could not be loaded from $resolvedFont"
}

$bitmap = [System.Drawing.Bitmap]::new($atlasSize, $atlasSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.Clear([System.Drawing.Color]::Transparent)
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font = [System.Drawing.Font]::new($fontCollection.Families[0], 118, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
$format = [System.Drawing.StringFormat]::new()
$format.Alignment = [System.Drawing.StringAlignment]::Center
$format.LineAlignment = [System.Drawing.StringAlignment]::Center
$format.FormatFlags = [System.Drawing.StringFormatFlags]::NoClip

for ($index = 0; $index -lt $characters.Length; $index++) {
    $column = $index % $columns
    $row = [Math]::Floor($index / $columns)
    $rect = [System.Drawing.RectangleF]::new($column * $cellSize, $row * $cellSize, $cellSize, $cellSize)
    $graphics.DrawString([string]$characters[$index], $font, $brush, $rect, $format)
}

$atlasPath = Join-Path $resolvedOutput "blanka-atlas.png"
$bitmap.Save($atlasPath, [System.Drawing.Imaging.ImageFormat]::Png)

$metadata = [ordered]@{
    family = $fontCollection.Families[0].Name
    characters = $characters
    columns = $columns
    rows = $rows
    cellSize = $cellSize
    atlasSize = $atlasSize
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $resolvedOutput "blanka-atlas.json") -Encoding UTF8

$format.Dispose()
$brush.Dispose()
$font.Dispose()
$graphics.Dispose()
$bitmap.Dispose()
$fontCollection.Dispose()

Write-Output "Created $atlasPath"
