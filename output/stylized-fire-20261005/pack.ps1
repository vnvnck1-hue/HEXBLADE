$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.IO;
using System.Collections.Generic;
public class FirePack {
public static void Run(string dir) {
using(var src=new Bitmap(Path.Combine(dir,"source_sheet_v1.png"))) {
var sdata=src.LockBits(new Rectangle(0,0,src.Width,src.Height),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
var raw=new byte[sdata.Stride*src.Height]; Marshal.Copy(sdata.Scan0,raw,0,raw.Length);src.UnlockBits(sdata);
Directory.CreateDirectory(Path.Combine(dir,"frames"));
var records=new List<string>();
using(var atlas=new Bitmap(1536,1536,PixelFormat.Format32bppArgb))
using(var ag=Graphics.FromImage(atlas)) {
ag.CompositingMode=CompositingMode.SourceCopy;
for(int i=0;i<12;i++) {
int x0=(int)Math.Round((i%4)*src.Width/4.0),x1=(int)Math.Round((i%4+1)*src.Width/4.0);
int y0=(int)Math.Round((i/4)*src.Height/3.0),y1=(int)Math.Round((i/4+1)*src.Height/3.0);
int baseY=0,baseL=0,baseR=0;
for(int y=y0+(y1-y0)/2;y<y1;y++) {
int l=x1,r=x0,n=0;
for(int x=x0;x<x1;x++){int at=y*sdata.Stride+x*4; if(raw[at+3]>=128 && raw[at+2]>140 && raw[at+1]>50){l=Math.Min(l,x);r=Math.Max(r,x);n++;}}
if(n>=60){baseY=y;baseL=l;baseR=r;}
}
if(baseY==0)throw new Exception("No flame base in cell "+i);
double rootX=(baseL+baseR)*0.5,scale=1.10,tx=192-rootX*scale,ty=464-baseY*scale;
using(var tile=src.Clone(new Rectangle(x0,y0,x1-x0,y1-y0),PixelFormat.Format32bppArgb))
using(var f=new Bitmap(384,512,PixelFormat.Format32bppArgb))
using(var fg=Graphics.FromImage(f)) {
fg.CompositingMode=CompositingMode.SourceCopy;fg.InterpolationMode=InterpolationMode.HighQualityBicubic;fg.PixelOffsetMode=PixelOffsetMode.HighQuality;
fg.DrawImage(tile,new RectangleF((float)(x0*scale+tx),(float)(y0*scale+ty),(float)(tile.Width*scale),(float)(tile.Height*scale)),new RectangleF(0,0,tile.Width,tile.Height),GraphicsUnit.Pixel);
f.Save(Path.Combine(dir,"frames/frame_"+i.ToString("D2")+".png"));
ag.DrawImageUnscaled(f,(i%4)*384,(i/4)*512);
records.Add("{\"frame\":"+i+",\"source_cell\":["+x0+","+y0+","+(x1-x0)+","+(y1-y0)+"],\"source_base\":["+rootX.ToString(System.Globalization.CultureInfo.InvariantCulture)+","+baseY+"],\"scale\":1.10,\"translation\":["+tx.ToString(System.Globalization.CultureInfo.InvariantCulture)+","+ty.ToString(System.Globalization.CultureInfo.InvariantCulture)+"]}");
}
}
atlas.Save(Path.Combine(dir,"fire_atlas.png"));
}
File.WriteAllText(Path.Combine(dir,"registration.json"),"["+string.Join(",",records)+"]");
Console.WriteLine("Packed 12 cells, 384x512, root (192,464), atlas 1536x1536; original RGBA preserved.");
}
}
}
'@
[FirePack]::Run($PSScriptRoot)
