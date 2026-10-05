local dir = app.params['dir']
assert(dir, 'dir required')
local ms = {80,70,70,70,90,70,70,80,90,100,100,110}
local sprite = Sprite(512,512,ColorMode.RGB)
sprite.layers[1].name = 'portrait'
for i=1,12 do
  if i>1 then sprite:newEmptyFrame(i) end
  local image = Image{fromFile=dir..'/frames/frame_'..string.format('%02d',i-1)..'.png'}
  sprite:newCel(sprite.layers[1],i,image,Point(0,0))
  sprite.frames[i].duration = ms[i]/1000
end
local tag=sprite:newTag(1,12)
tag.name='hairflip_wink_once'
sprite:saveAs(dir..'/hairflip_wink.aseprite')
app.sprite=sprite
-- GIF has binary transparency. Keep full RGBA only in PNG and the saved source.
local pc=app.pixelColor
for _,cel in ipairs(sprite.cels) do
  for it in cel.image:pixels() do
    local c=it()
    if pc.rgbaA(c)<128 then it(pc.rgba(0,0,0,0))
    else it(pc.rgba(pc.rgbaR(c),pc.rgbaG(c),pc.rgbaB(c),255)) end
  end
end
app.command.ColorQuantization{ui=false,withAlpha=false,maxColors=256,useRange=false,algorithm='octree'}
sprite.palettes[1]:saveAs(dir..'/gif_palette.gpl')
app.command.ChangePixelFormat{format='indexed',dithering='none'}
sprite:saveCopyAs(dir..'/hairflip_wink.gif')
print('GIF saved, 12 frames, 1000ms, 512x512')
