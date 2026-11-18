"""Render coordinate-tagged simulation samples without rescaling the pixels."""
from pathlib import Path
from PIL import Image
import sys,collections
variant=sys.argv[1] if len(sys.argv)>1 else 'reference'
data=Path(f'build/frame-{variant}.raw').read_bytes()
im=Image.new('L',(512,512)); coords=collections.Counter(); levels=collections.Counter()
for i in range(0,len(data)-4,5):
    x=int.from_bytes(data[i:i+2],'little'); y=int.from_bytes(data[i+2:i+4],'little'); v=data[i+4]
    if x<512 and y<512: im.putpixel((x,y),v); coords[y]+=1; levels[v]+=1
im.save(f'build/frame-{variant}.png')
im.crop((0,0,384,256)).resize((768,512),Image.Resampling.NEAREST).save(f'build/active-{variant}.png')
print(dict(samples=len(data)//5,rows=dict(coords),levels=dict(levels)))
