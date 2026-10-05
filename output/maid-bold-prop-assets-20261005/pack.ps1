$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public static class MaidPropsPack {
 public static void Run(string dir){
 var files=Directory.GetFiles(Path.Combine(dir,"masters"),"*.png");Array.Sort(files);if(files.Length!=11)throw new Exception("Expected11");
 var items=new List<string>();
 using(var sheet=new Bitmap(1024,924))using(var sg=Graphics.FromImage(sheet))using(var font=new Font("Arial",13)){
 sg.Clear(Color.FromArgb(30,35,50)); sg.InterpolationMode=InterpolationMode.HighQualityBicubic;
 for(int i=0;i<files.Length;i++)using(var src=new Bitmap(files[i])){
 int w=src.Width,h=src.Height;var d=src.LockBits(new Rectangle(0,0,w,h),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);byte[] b=new byte[d.Stride*h];Marshal.Copy(d.Scan0,b,0,b.Length);int stride=d.Stride;src.UnlockBits(d);
 int x0=w,y0=h,x1=0,y1=0,clear=0;
 for(int y=0;y<h;y++)for(int x=0;x<w;x++){byte a=b[y*stride+x*4+3];if(a==0)clear++;if(a>8){x0=Math.Min(x0,x);x1=Math.Max(x1,x);y0=Math.Min(y0,y);y1=Math.Max(y1,y);}}
 if(clear<w*h*.10)throw new Exception("No proper transparency: "+files[i]);
 double cx=(x0+x1)*.5,cy=(y0+y1)*.5,r=0;
 for(int y=0;y<h;y++)for(int x=0;x<w;x++)if(b[y*stride+x*4+3]>0)r=Math.Max(r,Math.Sqrt((x-cx)*(x-cx)+(y-cy)*(y-cy)));
 double scale=212/r;
 string id=Path.GetFileNameWithoutExtension(files[i]);
 using(var im=new Bitmap(512,512,PixelFormat.Format32bppArgb))using(var g=Graphics.FromImage(im)){
 g.CompositingMode=CompositingMode.SourceCopy;g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.PixelOffsetMode=PixelOffsetMode.HighQuality;
 g.DrawImage(src,new RectangleF((float)(256-cx*scale),(float)(256-cy*scale),(float)(w*scale),(float)(h*scale)),new RectangleF(0,0,w,h),GraphicsUnit.Pixel);
 string dest=Path.Combine(dir,"png",id+".png");im.Save(dest,ImageFormat.Png);
 int edge=0,nonzero=0;double maxr=0;
 var z=im.LockBits(new Rectangle(0,0,512,512),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);var arr=new byte[z.Stride*512];Marshal.Copy(z.Scan0,arr,0,arr.Length);int st=z.Stride;im.UnlockBits(z);
 for(int y=0;y<512;y++)for(int x=0;x<512;x++){int a=arr[y*st+x*4+3];if(a>0){nonzero++;maxr=Math.Max(maxr,Math.Sqrt((x-256)*(x-256)+(y-256)*(y-256)));if(x==0||y==0||x==511||y==511)edge++;}}
 if(edge>0||maxr>216)throw new Exception("Unsafe rotation bounds: "+id);
 int px=(i%4)*256,py=(i/4)*308;sg.DrawImage(im,new Rectangle(px,py,256,256));
 sg.DrawString(id.Replace('_',' '),font,Brushes.White,new RectangleF(px+8,py+266,245,40));
 items.Add(String.Format(System.Globalization.CultureInfo.InvariantCulture,"{{\"id\":\"{0}\",\"file\":\"png/{0}.png\",\"master_size\":[{1},{2}],\"size\":[512,512],\"pivot\":[256,256],\"pivot_uv\":[0.5,0.5],\"source_center\":[{3},{4}],\"scale\":{5},\"alpha_pixels\":{6},\"edge_pixels\":{7},\"max_alpha_radius\":{8}}}",id,w,h,cx,cy,scale,nonzero,edge,maxr));
 }
 }
 sheet.Save(Path.Combine(dir,"preview.png"),ImageFormat.Png);
 }
 File.WriteAllText(Path.Combine(dir,"manifest.json"),"{\"count\":11,\"format\":\"RGBA PNG\",\"rotation_safe\":true,\"assets\":["+String.Join(",\n",items)+"]}");
 }
}
'@
[MaidPropsPack]::Run($PSScriptRoot)
Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'manifest.json')
