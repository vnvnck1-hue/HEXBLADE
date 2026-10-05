"""Codex-owned Blender texture preparation. Run through tools/blender.ps1 wait.
The user requested Blender texturing: imagegen paint sources are made periodic,
assembled into a metric trim/prop atlas, and assigned to real Blender UVs.
"""
from pathlib import Path
import json
import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'output/codex-background-first-pass/source'
OUT = ROOT / 'assets/textures/codex_background'
N = 2048

def load_array(name):
    im = bpy.data.images.load(str(SRC / (name + '_source.png')), check_existing=False)
    im.scale(N, N)
    a = np.empty(N*N*4, np.float32)
    im.pixels.foreach_get(a)
    a = a.reshape(N,N,4).copy()
    bpy.data.images.remove(im)
    # Symmetric crossfade only in a 96px edge zone. The two edge values match.
    k = 96
    for axis in (0,1):
        b = np.moveaxis(a, axis, 0)
        for i in range(k):
            weight = .5*(1-i/k)**2
            lo, hi = b[i].copy(), b[-1-i].copy()
            b[i] = lo*(1-weight)+hi*weight
            b[-1-i] = hi*(1-weight)+lo*weight
    a[:,:,3] = 1
    return a

def save_image(name, a):
    im = bpy.data.images.new(name, width=N, height=N, alpha=True)
    im.colorspace_settings.name = 'sRGB'
    im.pixels.foreach_set(np.ascontiguousarray(a,np.float32).ravel())
    im.filepath_raw = str(OUT/(name+'.png'))
    im.file_format = 'PNG'
    im.save()
    bpy.data.images.remove(im)

def prepare():
    OUT.mkdir(parents=True,exist_ok=True)
    mats = {k:load_array(k) for k in ('violet','lavender','coral')}
    # Quiet the high-frequency strokes; retain genuine painted source variation.
    for name,a in mats.items():
        mean = a[:,:,:3].mean(axis=(0,1))
        a[:,:,:3] = mean+(a[:,:,:3]-mean)*(.62 if name=='violet' else .72)
    # Preserve broad brushwork but calm the blue saturation/value on the gameplay floor.
    floor=mats['violet'].copy()
    gray=floor[:,:,:3].mean(axis=2,keepdims=True)
    floor[:,:,:3]=(floor[:,:,:3]*.90+gray*.10)*.90
    save_image('bg_codex_base',floor)
    trim = np.ones((N,N,4),np.float32)
    bands=[(0,128,'coral',1.0),(128,384,'violet',.67),(384,512,'violet',1.07),
           (512,1024,'lavender',1.0),(1024,2048,'lavender',.95)]
    for x0,x1,k,g in bands:
        # Physical horizontal samples, not a compressed entire 4m image.
        trim[:,x0:x1] = mats[k][:,x0:x1]
        trim[:,x0:x1,:3] *= g
        u = np.linspace(0,1,x1-x0,dtype=np.float32)[None,:,None]
        trim[:,x0:x1,:3] *= .94+.06*np.sin(np.pi*u)
    # Selected warm paint chips along a reused trim edge. Not an all-over noise mask.
    yy,xx=np.mgrid[:N,:N]
    for cx,cy,rx,ry in [(388,210,3,18),(388,715,4,26),(388,1230,3,14),(388,1590,4,32)]:
        mask=np.maximum(0,1-((xx-cx)/rx)**2-((yy-cy)/ry)**2)**.7
        trim[:,:,:3]=trim[:,:,:3]*(1-mask[:,:,None]*.55)+mats['coral'][:,:,:3]*(mask[:,:,None]*.55)
    save_image('bg_codex_trim',trim)
    prop=np.ones((N,N,4),np.float32);prop[:,:,:3]=(.20,.16,.27)
    patches={
      'violet':(32,32,1024,1024,'violet',1.0),
      'coral':(32,1120,1024,512,'coral',1.0),
      'dark':(1120,32,896,896,'violet',.65),
      'lavender':(1120,1000,896,1016,'lavender',.95),
    }
    for name,(x,y,w,h,k,g) in patches.items():
        patch=mats[k][:h,:w].copy()
        if name=='lavender':
            patch[:,:,:3]=patch[:,:,:3]*.72+mats['violet'][:h,:w,:3]*.28
        patch[:,:,:3]*=g
        # Soft material-plane volume without a baked directional cast shadow.
        v=np.linspace(0,1,h,dtype=np.float32)[:,None,None]
        patch[:,:,:3]*=(.91+.09*np.sin(np.pi*v))
        if name in ('violet','coral'):
            py,px=np.mgrid[:h,:w]
            # Thin, softly broken edge catches + three small patches of worn paint.
            edge=np.exp(-px/2.5)*(.55+.45*np.sin(py*.013))
            patch[:,:,:3]*=1+.12*edge[:,:,None]
            for cy,ry in [(42,8),(180,14),(470,9)]:
                mask=np.maximum(0,1-((px-2)/3)**2-((py-cy)/ry)**2)**.8
                tint=mats['coral'][:h,:w,:3] if name=='violet' else np.minimum(1,patch[:,:,:3]*1.14)
                patch[:,:,:3]=patch[:,:,:3]*(1-mask[:,:,None]*.5)+tint*(mask[:,:,None]*.5)
        prop[y:y+h,x:x+w]=patch
        # 16px nearest-color extrusion; islands never sample a neighbor.
        prop[y-16:y,x:x+w]=patch[:1]
        prop[y+h:y+h+16,x:x+w]=patch[-1:]
        prop[y-16:y+h+16,x-16:x]=prop[y-16:y+h+16,x:x+1]
        prop[y-16:y+h+16,x+w:x+w+16]=prop[y-16:y+h+16,x+w-1:x+w]
    save_image('bg_codex_prop',prop)
    report={
      'texture_size':[N,N], 'density_px_m':512, 'period_m':4,
      'trim_widths_px':[128,256,128,512,1024], 'padding_px':16,
      'prop_patches':{k:list(v[:4]) for k,v in patches.items()},
      'base_edge_max_error':{
        'u':float(np.max(np.abs(floor[:,0]-floor[:,-1]))),
        'v':float(np.max(np.abs(floor[0]-floor[-1])))},
      'sources':'built-in imagegen; Blender image buffers / UV atlases',
    }
    (ROOT/'output/codex-background-first-pass/texture_report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
    print('CODEX_BACKGROUND_TEXTURES_OK',report['base_edge_max_error'])

if __name__=='__main__':
    prepare()
