#!/usr/bin/env python3
"""Render approved glyph artwork as Android launcher layers. No AI image generation."""
from pathlib import Path
import re, subprocess, tempfile, argparse
from PIL import Image, ImageChops, ImageDraw, ImageFont

root=Path(__file__).resolve().parents[1]
source=root/'flutter/assets/branding/kachat-photo-symbols.svg'
images=root/'flutter/assets/images';res=root/'flutter/android/app/src/main/res'
text=source.read_text()
# Remove the single solid background, retaining every original glyph and its position.
transparent=re.sub(r'<rect\b[^>]*\bfill="#020704"[^>]*/>', '',text,count=1)
assert transparent!=text
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);(p/'foreground.svg').write_text(transparent)
 subprocess.run(['rsvg-convert',str(source),'-o',str(images/'kachat-icon.png')],check=True)
 subprocess.run(['rsvg-convert',str(p/'foreground.svg'),'-o',str(images/'kachat-foreground.png')],check=True)
color=Image.open(images/'kachat-icon.png').convert('RGBA')
foreground=Image.open(images/'kachat-foreground.png').convert('RGBA')
# The approved artwork already includes margins; let the launcher mask crop
# the full-size photograph without adding a second large border around it.
adaptive_inset=8
# Android tint uses alpha, so preserve the original luminance in that channel.
light=foreground.convert('L'); maximum=light.getextrema()[1]
normalized=light.point(lambda n:round(n*255/maximum))
alpha=ImageChops.multiply(foreground.getchannel('A'),normalized)
mono=Image.new('RGBA',foreground.size,'white');mono.putalpha(alpha)
mono.save(images/'kachat-monochrome.png')
for density,scale in [('mdpi',1),('hdpi',1.5),('xhdpi',2),('xxhdpi',3),('xxxhdpi',4)]:
 mip=res/f'mipmap-{density}';draw=res/f'drawable-{density}';mip.mkdir(exist_ok=True);draw.mkdir(exist_ok=True)
 color.resize((round(48*scale),)*2,Image.Resampling.LANCZOS).save(mip/'ic_launcher.png')
 foreground.resize((round(108*scale),)*2,Image.Resampling.LANCZOS).save(draw/'ic_launcher_foreground.png')
 mono.resize((round(108*scale),)*2,Image.Resampling.LANCZOS).save(draw/'ic_launcher_monochrome.png')

# Actual 108dp layer -> central 72dp viewport -> launcher circle, at a displayable size.
def preview(layer,bg,fg=None):
 canvas=Image.new('RGBA',(768,768),bg)
 if fg:
  layer=Image.new('RGBA',mono.size,fg);layer.putalpha(alpha)
 side=round(768*(1-2*adaptive_inset/100));offset=(768-side)//2
 canvas.alpha_composite(layer.resize((side,side),Image.Resampling.LANCZOS),(offset,offset))
 canvas=canvas.crop((128,128,640,640))
 mask=Image.new('L',(512,512),0);ImageDraw.Draw(mask).ellipse((0,0,511,511),fill=255)
 canvas.putalpha(mask);return canvas
parser=argparse.ArgumentParser()
parser.add_argument('--preview-dir',type=Path,default=root/'build/branding')
out=parser.parse_args().preview_dir
out.mkdir(parents=True,exist_ok=True)
sheet=Image.new('RGB',(1420,640),'#101512');draw=ImageDraw.Draw(sheet)
font=ImageFont.truetype('/usr/share/fonts/noto/NotoSans-Regular.ttf',23)
variants=[('Обычная иконка',foreground,'#020704',None),('Пример светлой темы',mono,'#dce7cf','#334c28'),('Пример тёмной темы',mono,'#263b50','#b8d8f9')]
for x,(label,layer,bg,fg) in zip([30,500,970],variants):
 icon=preview(layer,bg,fg).resize((420,420),Image.Resampling.LANCZOS)
 sheet.paste(icon,(x,90),icon);draw.text((x+12,535),label,font=font,fill='#d4e2d7')
sheet.save(out/'kachat-themed-preview.png')
print('Prepared approved icon, adaptive foreground, alpha-only monochrome and theme previews.')
