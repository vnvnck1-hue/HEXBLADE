local dir=app.params['dir']
assert(dir, 'dir required')
local sprite=Sprite(384,512,ColorMode.RGB)
sprite.layers[1].name='flame'
for i=1,12 do
  if i>1 then sprite:newEmptyFrame(i) end
  sprite:newCel(sprite.layers[1],i,Image{fromFile=dir..'/frames/frame_'..string.format('%02d',i-1)..'.png'},Point(0,0))
  sprite.frames[i].duration=0.08
end
local tag=sprite:newTag(1,12)
tag.name='fire_loop'
sprite:saveAs(dir..'/fire_loop.aseprite')
app.sprite=sprite
local pc=app.pixelColor
for _,cel in ipairs(sprite.cels) do
  for it in cel.image:pixels() do
    local c=it()
    if pc.rgbaA(c)<128 then it(pc.rgba(0,0,0,0))
    else it(pc.rgba(pc.rgbaR(c),pc.rgbaG(c),pc.rgbaB(c),255)) end
  end
end
app.command.ColorQuantization{ui=false,withAlpha=false,maxColors=256,useRange=false,algorithm='octree'}
app.command.ChangePixelFormat{format='indexed',dithering='none'}
sprite:saveCopyAs(dir..'/fire_loop.gif')
-- Dark reference-color preview, retaining the same timing and registration.
local preview=Sprite(384,512,ColorMode.RGB)
preview.layers[1].name='preview'
for i=1,12 do
  if i>1 then preview:newEmptyFrame(i) end
  local im=Image(384,512,ColorMode.RGB)
  im:clear(pc.rgba(64,53,65,255))
  im:drawImage(Image{fromFile=dir..'/frames/frame_'..string.format('%02d',i-1)..'.png'},Point(0,0))
  preview:newCel(preview.layers[1],i,im,Point(0,0))
  preview.frames[i].duration=0.08
end
app.sprite=preview
app.command.ColorQuantization{ui=false,withAlpha=false,maxColors=256,useRange=false,algorithm='octree'}
app.command.ChangePixelFormat{format='indexed',dithering='none'}
preview:saveCopyAs(dir..'/fire_preview.gif')
print('GIF files saved: 12 frames x 80ms = 960ms loop')
