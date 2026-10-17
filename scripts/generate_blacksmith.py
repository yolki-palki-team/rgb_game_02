"""Original CC0 blacksmith and forge, matching RuneForge's 40px actor palette."""
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]/'game/assets'
sheet=Image.new('RGBA',(160,48))
for frame in range(4):
 im=Image.new('RGBA',(40,48));d=ImageDraw.Draw(im);b=[0,-1,0,1][frame]
 d.ellipse((7,41,33,47),fill='#17242b')
 d.rectangle((12,33,18,43),fill='#35444a');d.rectangle((23,33,29,43),fill='#35444a')
 d.rectangle((10,42,18,45),fill='#665547');d.rectangle((23,42,31,45),fill='#665547')
 d.polygon([(12,20+b),(28,20+b),(31,38),(9,38)],fill='#b88858',outline='#17242b')
 d.rectangle((13,23+b,27,38),fill='#694638');d.line((15,24+b,15,36),fill='#9e7051')
 d.rectangle((13,30,27,32),fill='#362f2d');d.rectangle((19,30,22,32),fill='#d9bd83')
 d.rectangle((8,22+b,12,31+b),fill='#d3a57d');d.rectangle((29,22+b,33,31+b),fill='#d3a57d')
 d.rectangle((14,8+b,27,21+b),fill='#d3a57d',outline='#24272b')
 d.polygon([(13,12+b),(14,7+b),(25,5+b),(28,10+b),(24,10+b),(24,8+b),(18,9+b),(17,12+b)],fill='#544137')
 d.rectangle((16,13+b,18,14+b),fill='#202d35');d.rectangle((23,13+b,25,14+b),fill='#202d35')
 d.polygon([(14,17+b),(18,19+b),(21,18+b),(25,18+b),(27,16+b),(26,23+b),(21,26+b),(15,23+b)],fill='#795e43')
 d.line((17,22+b,22,23+b),fill='#b3a082');d.line((16,17+b,24,17+b),fill='#9b7455')
 # Raised steel hammer; subtle breathing and sparks suggest a working forge.
 lift=[0,-3,-6,-2][frame];d.line((33,32+b,34,17+lift),fill='#ad855b',width=2)
 d.rectangle((29,14+lift,38,19+lift),fill='#83969a',outline='#26343f');d.line((30,14+lift,37,14+lift),fill='#d2d6c1')
 sheet.alpha_composite(im,(40*frame,0))
sheet.save(ROOT/'blacksmith.png')
im=Image.new('RGBA',(64,64));d=ImageDraw.Draw(im)
d.ellipse((2,52,61,63),fill='#17242b');d.polygon([(18,35),(43,35),(49,59),(12,59)],fill='#654939',outline='#24272b')
for x in (18,25,33,41):d.line((x,40,x-3,56),fill='#9b7150')
d.polygon([(7,22),(53,22),(58,28),(43,31),(40,38),(45,42),(16,42),(22,37),(22,31),(7,28)],fill='#526571',outline='#1b2932')
d.polygon([(3,20),(53,20),(60,24),(16,26)],fill='#9dadad');d.line((9,21,51,21),fill='#d9ddc4')
d.rectangle((29,20,42,22),fill='#ffac55');d.line((31,19,39,19),fill='#ffe0a0')
d.point((36,13),fill='#f4bc69');d.point((43,9),fill='#f4bc69');d.point((27,14),fill='#d17b4c')
im.save(ROOT/'anvil.png')
