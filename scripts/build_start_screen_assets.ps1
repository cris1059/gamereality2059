param(
    [string]$BackgroundPath = "assets-source\ui\reality2059-start-background.png",
    [string]$FontPath = "Modelos Personajes\blanka-free-for-commercial-use\blanka-free-for-commercial-use\Blanka.otf",
    [string]$OutputDirectory = "assets-source\ui"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$backgroundFile = (Resolve-Path -LiteralPath $BackgroundPath).Path
$fontFile = (Resolve-Path -LiteralPath $FontPath).Path
$output = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputDirectory))
[System.IO.Directory]::CreateDirectory($output) | Out-Null

$source = [System.Drawing.Bitmap]::FromFile($backgroundFile)
$halfWidth = [Math]::Floor($source.Width / 2)
$halves = @(
    @{ Name = "reality2059-start-background-left.png"; X = 0; Width = $halfWidth },
    @{ Name = "reality2059-start-background-right.png"; X = $halfWidth; Width = $source.Width - $halfWidth }
)
foreach ($half in $halves) {
    $bitmap = [System.Drawing.Bitmap]::new($half.Width, $source.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.DrawImage(
        $source,
        [System.Drawing.Rectangle]::new(0, 0, $half.Width, $source.Height),
        [System.Drawing.Rectangle]::new($half.X, 0, $half.Width, $source.Height),
        [System.Drawing.GraphicsUnit]::Pixel
    )
    $bitmap.Save((Join-Path $output $half.Name), [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
}
$source.Dispose()

$fontCollection = [System.Drawing.Text.PrivateFontCollection]::new()
$fontCollection.AddFontFile($fontFile)
$family = $fontCollection.Families[0]
$overlay = [System.Drawing.Bitmap]::new(940, 940, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$canvas = [System.Drawing.Graphics]::FromImage($overlay)
$canvas.Clear([System.Drawing.Color]::Transparent)
$canvas.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$canvas.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

$white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 242, 248, 255))
$muted = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(235, 190, 199, 211))
$format = [System.Drawing.StringFormat]::new()
$format.Alignment = [System.Drawing.StringAlignment]::Center
$format.LineAlignment = [System.Drawing.StringAlignment]::Center
$format.FormatFlags = [System.Drawing.StringFormatFlags]::NoClip

function Draw-CenteredText([string]$Text, [float]$Y, [float]$Height, [float]$Size, [System.Drawing.Brush]$Brush) {
    $font = [System.Drawing.Font]::new($family, $Size, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $rect = [System.Drawing.RectangleF]::new(0, $Y, 940, $Height)
    $canvas.DrawString($Text, $font, $Brush, $rect, $format)
    $font.Dispose()
}

Draw-CenteredText "REALITY" 205 145 142 $white
Draw-CenteredText "2059" 325 135 128 $white
Draw-CenteredText "LA REALIDAD NO ESTA ROTA." 485 42 28 $white
Draw-CenteredText "ALGUIEN LA ESTA REESCRIBIENDO." 523 42 24 $white
Draw-CenteredText "INICIAR" 615 64 54 $white
Draw-CenteredText "CONTINUAR" 704 42 30 $muted
Draw-CenteredText "AJUSTES" 753 42 30 $muted
Draw-CenteredText "CREDITOS" 802 42 30 $muted

$overlay.Save((Join-Path $output "reality2059-start-blanka-overlay.png"), [System.Drawing.Imaging.ImageFormat]::Png)

$format.Dispose()
$muted.Dispose()
$white.Dispose()
$canvas.Dispose()
$overlay.Dispose()
$fontCollection.Dispose()

Write-Output "Created split background and exact BLANKA overlay in $output"
