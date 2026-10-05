$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$out = $PSScriptRoot
$src = 'C:\Users\vnvnc\.codex\attachments\f62ab4a6-64ac-42bc-95a3-bdee31966948\image-1.gif'
$im = [Drawing.Image]::FromFile($src)
$dim = [Drawing.Imaging.FrameDimension]::Time
$count = $im.GetFrameCount($dim)
$delays = $im.GetPropertyItem(0x5100).Value
$durations = @(for ($i=0; $i -lt $count; $i++) { [BitConverter]::ToInt32($delays,$i*4)*10 })
$sheet = New-Object Drawing.Bitmap (1440,([int][Math]::Ceiling($count/6.0)*280))
$g = [Drawing.Graphics]::FromImage($sheet)
$g.Clear([Drawing.Color]::FromArgb(64,53,65))
$font = New-Object Drawing.Font('Arial',10)
$boxes = @()
for ($i=0; $i -lt $count; $i++) {
    [void]$im.SelectActiveFrame($dim,$i)
    $f = New-Object Drawing.Bitmap $im
    $minx=1280; $miny=720; $maxx=0; $maxy=0
    for($y=0; $y -lt 720; $y+=2) { for($x=0; $x -lt 1280; $x+=2) {
        $c=$f.GetPixel($x,$y)
        if($c.R -gt 150 -and $c.G -gt 60) { $minx=[Math]::Min($x,$minx); $miny=[Math]::Min($y,$miny); $maxx=[Math]::Max($x,$maxx); $maxy=[Math]::Max($y,$maxy) }
    }}
    $boxes += ,@($minx,$miny,($maxx+2),($maxy+2))
    $tx=($i%6)*240; $ty=[int][Math]::Floor($i/6)*280
    $g.DrawImage($f, (New-Object Drawing.Rectangle ($tx+5),($ty+20),230,250), (New-Object Drawing.Rectangle 400,130,440,480),[Drawing.GraphicsUnit]::Pixel)
    $g.DrawString(('{0:D2} / {1}ms' -f ($i+1),$durations[$i]),$font,[Drawing.Brushes]::White,$tx+8,$ty+3)
    if($i -in @(0,[int]($count/4),[int]($count/2),[int](3*$count/4))) {
        $f.Clone((New-Object Drawing.Rectangle 400,130,440,480),[Drawing.Imaging.PixelFormat]::Format32bppArgb).Save((Join-Path $out ('reference_phase_{0:D2}.png' -f $i)))
    }
    $f.Dispose()
}
$g.Dispose()
$sheet.Save((Join-Path $out 'reference_contact.png'))
$palette=@($im.Palette.Entries | ForEach-Object { '#{0:X2}{1:X2}{2:X2}' -f $_.R,$_.G,$_.B })
$report=@{size=@($im.Width,$im.Height);frame_count=$count;durations_ms=$durations;total_ms=($durations | Measure-Object -Sum).Sum;frame_bboxes=$boxes;palette=$palette;sha256=(Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'reference_analysis.json') -Encoding UTF8
Copy-Item -LiteralPath $src -Destination (Join-Path $out 'reference.gif')
$im.Dispose()
[pscustomobject]$report | Select-Object size,frame_count,total_ms,durations_ms | ConvertTo-Json -Depth 4
