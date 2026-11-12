# Builds the Windows app icon (.ico, PNG frames) from assets/icon/ops.svg.
# Reads only <rect rx> and <polygon> elements; the background stays transparent, in document order; fills are #rrggbb.
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Svg = (Join-Path $PSScriptRoot '..\assets\icon\ops.svg'),
  [string]$Out = (Join-Path $PSScriptRoot '..\windows\runner\resources\app_icon.ico'),
  [int[]]$Sizes = @(16, 24, 32, 48, 256)
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$doc = [xml](Get-Content -Raw $Svg)
$view = [double[]]($doc.svg.viewBox -split '\s+')
$shapes = @($doc.svg.ChildNodes | Where-Object { $_.LocalName -in 'rect', 'polygon' })
$inv = [Globalization.CultureInfo]::InvariantCulture

function Get-Color($hex) { [Drawing.ColorTranslator]::FromHtml($hex) }

function Get-Path($node) {
  $p = New-Object Drawing.Drawing2D.GraphicsPath
  if ($node.LocalName -eq 'rect') {
    $x = [single]::Parse($node.x, $inv); $y = [single]::Parse($node.y, $inv)
    $w = [single]::Parse($node.width, $inv); $h = [single]::Parse($node.height, $inv)
    $d = 2 * [single]::Parse($node.rx, $inv)
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
  } else {
    $pts = foreach ($pair in ($node.points.Trim() -split '\s+')) {
      $xy = $pair -split ','
      New-Object Drawing.PointF ([single]::Parse($xy[0], $inv)), ([single]::Parse($xy[1], $inv))
    }
    $p.AddPolygon([Drawing.PointF[]]$pts)
  }
  $p
}

# draw at 4x and shrink, so the small sizes get clean edges
function New-Frame([int]$size) {
  $big = $size * 4
  $src = New-Object Drawing.Bitmap $big, $big, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($src)
  $g.SmoothingMode = 'AntiAlias'
  $g.ScaleTransform($big / $view[2], $big / $view[3])
  foreach ($s in $shapes) {
    $brush = New-Object Drawing.SolidBrush (Get-Color $s.fill)
    $g.FillPath($brush, (Get-Path $s))
  }
  $g.Dispose()
  $dst = New-Object Drawing.Bitmap $size, $size, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($dst)
  $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
  $edge = New-Object Drawing.Imaging.ImageAttributes
  $edge.SetWrapMode('TileFlipXY')
  $g.DrawImage($src, (New-Object Drawing.Rectangle 0, 0, $size, $size), 0, 0, $big, $big, 'Pixel', $edge)
  $g.Dispose(); $src.Dispose()
  $ms = New-Object IO.MemoryStream
  $dst.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $dst.Dispose()
  , $ms.ToArray()
}

$frames = foreach ($n in $Sizes) { , (New-Frame $n) }
$ms = New-Object IO.MemoryStream
$w = New-Object IO.BinaryWriter $ms
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$Sizes.Count)
$offset = 6 + 16 * $Sizes.Count
for ($i = 0; $i -lt $Sizes.Count; $i++) {
  $n = $Sizes[$i]; $dim = if ($n -ge 256) { 0 } else { $n }
  $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
  $w.Write([uint16]1); $w.Write([uint16]32)
  $w.Write([uint32]$frames[$i].Length); $w.Write([uint32]$offset)
  $offset += $frames[$i].Length
}
foreach ($f in $frames) { $w.Write($f) }
$w.Flush()

$out = [IO.Path]::GetFullPath($Out)
if ($PSCmdlet.ShouldProcess($out, 'write icon')) {
  [IO.File]::WriteAllBytes($out, $ms.ToArray())
  '{0,6} {1}' -f 'wrote', (Resolve-Path -Relative $out)
}
