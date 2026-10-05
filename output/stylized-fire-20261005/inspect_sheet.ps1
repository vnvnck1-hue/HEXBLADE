$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$im = [Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'source_sheet_v1.png'))
$bg = New-Object Drawing.Bitmap $im.Width,$im.Height
$g = [Drawing.Graphics]::FromImage($bg)
$g.Clear([Drawing.Color]::FromArgb(64,53,65))
$g.DrawImageUnscaled($im,0,0)
$g.Dispose()
$bg.Save((Join-Path $PSScriptRoot 'sheet_v1_dark.png'))
Write-Output ('size: {0} x {1}, corner alpha {2}' -f $im.Width,$im.Height,$im.GetPixel(0,0).A)
$im.Dispose(); $bg.Dispose()
