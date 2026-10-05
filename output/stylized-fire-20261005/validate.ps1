$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.IO;
using System.Collections.Generic;
public class FireValidation {
public static string Check(string dir) {
var rows=new List<string>(); var masks=new List<byte[]>();
for(int i=0;i<12;i++)using(var im=new Bitmap(Path.Combine(dir,"frames/frame_"+i.ToString("D2")+".png"))) {
if(im.Width!=384||im.Height!=512)throw new Exception("Unexpected canvas");
var data=im.LockBits(new Rectangle(0,0,384,512),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
var b=new byte[data.Stride*512];Marshal.Copy(data.Scan0,b,0,b.Length);im.UnlockBits(data);
int l=384,t=512,r=-1,bot=-1,edge=0,soft=0,n=0;var mask=new byte[384*512];
for(int y=0;y<512;y++)for(int x=0;x<384;x++) {
int a=b[y*data.Stride+x*4+3];if(a>0&&a<255)soft++;
if(a>=128){l=Math.Min(l,x);t=Math.Min(t,y);r=Math.Max(r,x);bot=Math.Max(bot,y);n++;mask[y*384+x]=1;if(x==0||y==0||x==383||y==511)edge++;}
}
if(edge>0||n<3000)throw new Exception("Clipped or empty frame "+i);
masks.Add(mask);rows.Add("{\"index\":"+i+",\"bbox_alpha128\":["+l+","+t+","+r+","+bot+"],\"opaque_pixels\":"+n+",\"soft_alpha_pixels\":"+soft+",\"edge_pixels\":"+edge+"}");
}
var delta=new List<double>();for(int i=0;i<12;i++) {int different=0,union=0;var a=masks[i];var b=masks[(i+1)%12];for(int p=0;p<a.Length;p++){if(a[p]!=b[p])different++;if(a[p]!=0||b[p]!=0)union++;}delta.Add((double)different/union);}
double sum=0,max=0;for(int i=0;i<11;i++){sum+=delta[i];max=Math.Max(max,delta[i]);}
if(delta[11]>max)throw new Exception("Loop seam exceeds every interior transition");
Console.WriteLine("Alpha silhouette deltas "+string.Join(", ",delta));
return "{\"frames\":["+string.Join(",",rows)+"],\"silhouette_delta\":["+string.Join(",",delta.ConvertAll(v=>v.ToString(System.Globalization.CultureInfo.InvariantCulture)))+"],\"seam_delta\":"+delta[11].ToString(System.Globalization.CultureInfo.InvariantCulture)+",\"mean_interior_delta\":"+(sum/11).ToString(System.Globalization.CultureInfo.InvariantCulture)+",\"max_interior_delta\":"+max.ToString(System.Globalization.CultureInfo.InvariantCulture)+"}";
}
}
'@
$data=[FireValidation]::Check($PSScriptRoot) | ConvertFrom-Json
$gifs=@()
foreach($name in @('fire_loop.gif','fire_preview.gif')) {
 $gif=[Drawing.Image]::FromFile((Join-Path $PSScriptRoot $name))
 $dim=[Drawing.Imaging.FrameDimension]::Time
 $delay=$gif.GetPropertyItem(0x5100).Value
 $ms=@(for($i=0;$i -lt $delay.Length;$i+=4){[BitConverter]::ToUInt32($delay,$i)*10})
 $loop=[BitConverter]::ToUInt16($gif.GetPropertyItem(0x5101).Value,0)
 $gifs+=@{file=$name;size=@($gif.Width,$gif.Height);frames=$gif.GetFrameCount($dim);durations_ms=$ms;total_ms=($ms|Measure-Object -Sum).Sum;loop_count=$loop;sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash}
 $gif.Dispose()
}
$atlas=[Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'fire_atlas.png'))
$reg=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'registration.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$maxError=0.0
foreach($r in $reg){$dx=$r.source_base[0]*$r.scale+$r.translation[0]-192;$dy=$r.source_base[1]*$r.scale+$r.translation[1]-464;$maxError=[Math]::Max($maxError,[Math]::Sqrt($dx*$dx+$dy*$dy))}
$pass=(@($gifs|Where-Object {$_.frames -ne 12 -or $_.total_ms -ne 960 -or $_.loop_count -ne 0}).Count -eq 0 -and $atlas.Width -eq 1536 -and $atlas.Height -eq 1536 -and $maxError -lt 0.001)
$result=@{pass=$pass;gifs=$gifs;atlas_canvas=@($atlas.Width,$atlas.Height);root_transform_max_error_px=$maxError;alpha_check=$data;method='RGBA frame checks, GIF re-decoding/timing/loop metadata, forward silhouette delta including seam; no optical-flow claim'}
$atlas.Dispose()
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'validation.json') -Encoding UTF8
Write-Output ('PASS={0}, GIF 12 x 80ms = 960ms, atlas1536x1536, root error {1}' -f $pass,$maxError)
if(-not $pass){throw 'Validation failed'}
