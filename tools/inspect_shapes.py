from pathlib import Path
from PIL import Image,ImageDraw
R=lambda n:[int(x,16) for x in Path('roms/cdi.'+n+'.hex').read_text().split()]
r=[R(n) for n in ['b8','c8','d8','e8']]
im=Image.new('RGB',(800,240));d=ImageDraw.Draw(im)
for code in range(16):
    ox=(code%8)*100;oy=(code//8)*120
    d.text((ox,oy),str(code),fill='white')
    for y in range(16):
        v=sum((r[i][code*16+y]&15)<<(12-i*4) for i in range(4))
        for x in range(16):
            if v&(1<<(15-x)):d.rectangle((ox+x*5,oy+20+y*5,ox+x*5+4,oy+24+y*5),fill='white')
im.save('build/shape-atlas.png')
