param([switch]$InspectOnly)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.IO;
public class HairPack {
 public class Part { public List<int> P=new List<int>(); public int X=99999,Y=99999,R=0,B=0; public double CX,CY; }
 public static void Run(string dir,bool inspect){
 using(var src=new Bitmap(Path.Combine(dir,"source_sheet.png"))){
 int w=src.Width,h=src.Height; var data=src.LockBits(new Rectangle(0,0,w,h),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
 byte[] raw=new byte[data.Stride*h]; Marshal.Copy(data.Scan0,raw,0,raw.Length); int stride=data.Stride; src.UnlockBits(data);
 bool[] seen=new bool[w*h]; var parts=new List<Part>(); var q=new Queue<int>();
 for(int k=0;k<w*h;k++) { if(seen[k] || raw[(k/w)*stride+(k%w)*4+3]<16)continue;
 var p=new Part(); q.Enqueue(k); seen[k]=true;
 while(q.Count>0){int v=q.Dequeue(),x=v%w,y=v/w; p.P.Add(v);p.X=Math.Min(p.X,x);p.Y=Math.Min(p.Y,y);p.R=Math.Max(p.R,x);p.B=Math.Max(p.B,y);
 for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){int nx=x+dx,ny=y+dy;if(nx<0||nx>=w||ny<0||ny>=h)continue;int n=ny*w+nx;if(!seen[n]&&raw[ny*stride+nx*4+3]>=16){seen[n]=true;q.Enqueue(n);}} }
 if(p.P.Count>1500)parts.Add(p);
 }
 parts.Sort((a,b)=> {int ar=(int)((a.Y+a.B)*0.5/(h/3.0)),br=(int)((b.Y+b.B)*0.5/(h/3.0));return ar==br?a.X.CompareTo(b.X):ar.CompareTo(br);});
 Console.WriteLine("SOURCE "+w+"x"+h+" PARTS "+parts.Count);
 for(int i=0;i<parts.Count;i++){var p=parts[i]; Console.WriteLine(i+": "+p.X+","+p.Y+" - "+p.R+","+p.B+" pixels="+p.P.Count);}
 if(inspect)return; if(parts.Count!=12)throw new Exception("Expected twelve isolated subjects");
 Directory.CreateDirectory(Path.Combine(dir,"frames"));
 var records=new List<string>();
 using(var atlas=new Bitmap(2048,1536,PixelFormat.Format32bppArgb))using(var ag=Graphics.FromImage(atlas)){
 ag.CompositingMode=CompositingMode.SourceCopy;
 for(int i=0;i<12;i++){
 var p=parts[i]; double cellCenter=((i%4)+0.5)*w/4.0;
 // Registration uses the gold belt buckle, not the moving hair silhouette.
 double sx=0,sy=0,n=0;int left=99999,right=0,top=99999,bottom=0;
 var gold=new HashSet<int>();
 foreach(int v in p.P){int x=v%w,y=v/w;int at=y*stride+x*4;int b=raw[at],g=raw[at+1],r=raw[at+2];
 if(Math.Abs(x-cellCenter)<w/4.0*.09 && y>p.B-h/3.0*.12 && r>145&&g>110&&r>b*1.32&&g>b*1.14)gold.Add(v);}
 var goldSeen=new HashSet<int>();var best=new List<int>();
 foreach(int start in gold){if(goldSeen.Contains(start))continue;var cluster=new List<int>();q.Enqueue(start);goldSeen.Add(start);
 while(q.Count>0){int v=q.Dequeue();cluster.Add(v);int x=v%w,y=v/w;for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){int nn=(y+dy)*w+x+dx;if(gold.Contains(nn)&&goldSeen.Add(nn))q.Enqueue(nn);}}
 if(cluster.Count>best.Count)best=cluster;}
 foreach(int v in best){int x=v%w,y=v/w;sx+=x;sy+=y;n++;left=Math.Min(left,x);right=Math.Max(right,x);top=Math.Min(top,y);bottom=Math.Max(bottom,y);}
 if(n<15)throw new Exception("Cannot locate buckle "+i);
 p.CX=(left+right)*.5;p.CY=(top+bottom)*.5;
 double scale=1.14;double tx=256-p.CX*scale,ty=450-p.CY*scale;
 using(var isolated=new Bitmap(w,h,PixelFormat.Format32bppArgb)){
 var dd=isolated.LockBits(new Rectangle(0,0,w,h),ImageLockMode.WriteOnly,PixelFormat.Format32bppArgb);var dst=new byte[dd.Stride*h];
 // Preserve original RGBA plus one pixel of soft alpha edge around the connected component.
 foreach(int v in p.P){int x=v%w,y=v/w;for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){int xx=x+dx,yy=y+dy;if(xx<0||xx>=w||yy<0||yy>=h)continue;int a=yy*stride+xx*4,t=yy*dd.Stride+xx*4;Buffer.BlockCopy(raw,a,dst,t,4);}}
 Marshal.Copy(dst,0,dd.Scan0,dst.Length);isolated.UnlockBits(dd);
 using(var frame=new Bitmap(512,512,PixelFormat.Format32bppArgb))using(var fg=Graphics.FromImage(frame)){
 fg.CompositingMode=CompositingMode.SourceCopy;fg.InterpolationMode=InterpolationMode.HighQualityBicubic;fg.PixelOffsetMode=PixelOffsetMode.HighQuality;
 fg.DrawImage(isolated,new RectangleF((float)tx,(float)ty,(float)(w*scale),(float)(h*scale)),new RectangleF(0,0,w,h),GraphicsUnit.Pixel);
 frame.Save(Path.Combine(dir,"frames",String.Format("frame_{0:00}.png",i)),ImageFormat.Png);
 ag.DrawImageUnscaled(frame,(i%4)*512,(i/4)*512);
 records.Add(String.Format(System.Globalization.CultureInfo.InvariantCulture,"{{\"frame\":{0},\"source_buckle\":[{1},{2}],\"scale\":{3},\"translation\":[{4},{5}],\"registered_buckle\":[256,450],\"pivot_px\":[256,409.6]}}",i,p.CX,p.CY,scale,tx,ty));
 }
 }
 }
 atlas.Save(Path.Combine(dir,"hairflip_atlas.png"),ImageFormat.Png);
 }
 File.WriteAllText(Path.Combine(dir,"registration.json"),"["+String.Join(",\n",records)+"]");
 }
 }
}
'@
[HairPack]::Run($PSScriptRoot,$InspectOnly.IsPresent)
