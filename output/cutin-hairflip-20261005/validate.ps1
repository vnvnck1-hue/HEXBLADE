$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$gif=[Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'hairflip_wink.gif'))
$dim=[Drawing.Imaging.FrameDimension]::new($gif.FrameDimensionsList[0])
$delays=$gif.GetPropertyItem(0x5100).Value
$ms=@(for($i=0;$i -lt $delays.Length;$i+=4){[BitConverter]::ToUInt32($delays,$i)*10})
$result=[ordered]@{gif_canvas=@($gif.Width,$gif.Height);gif_frames=$gif.GetFrameCount($dim);durations_ms=$ms;total_ms=($ms|Measure-Object -Sum).Sum;frames=@()}
$gif.Dispose()
$reg=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'registration.json') | ConvertFrom-Json
foreach($record in $reg){
 $f=Join-Path $PSScriptRoot ('frames/frame_{0:00}.png' -f $record.frame)
 $im=[Drawing.Bitmap]::FromFile($f)
 $edge=0;$minX=512;$minY=512;$maxX=0;$maxY=0;$soft=0
 for($y=0;$y -lt 512;$y++){for($x=0;$x -lt 512;$x++){
  $a=$im.GetPixel($x,$y).A
  if($a -gt 0 -and $a -lt 255){$soft++}
  if($a -gt 8){$minX=[Math]::Min($minX,$x);$minY=[Math]::Min($minY,$y);$maxX=[Math]::Max($maxX,$x);$maxY=[Math]::Max($maxY,$y);if($x -eq 0 -or $y -eq 0 -or $x -eq 511 -or $y -eq 511){$edge++}}
 }}
 $measuredX=$record.source_buckle[0]*$record.scale+$record.translation[0]
 $measuredY=$record.source_buckle[1]*$record.scale+$record.translation[1]
 $err=[Math]::Sqrt([Math]::Pow($measuredX-256,2)+[Math]::Pow($measuredY-450,2))
 $result.frames+=@{index=$record.frame;canvas=@($im.Width,$im.Height);alpha_bounds=@($minX,$minY,$maxX,$maxY);canvas_edge_pixels=$edge;soft_alpha_pixels=$soft;registration_transform_error_px=$err;sha256=(Get-FileHash -LiteralPath $f).Hash}
 $im.Dispose()
}
$result['pass']=($result.gif_frames -eq 12 -and $result.total_ms -eq 1000 -and @($result.frames|Where-Object {$_.canvas_edge_pixels -gt 0 -or $_.registration_transform_error_px -gt 0.001}).Count -eq 0)
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'validation.json'),($result|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
$result|ConvertTo-Json -Depth 6
if(-not $result.pass){throw 'Validation failed'}
