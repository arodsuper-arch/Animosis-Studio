"""Render hillshade previews (red graticule every 0.02 deg) for every site."""
import os, sys
from demlib import crop, save_png
from sites import SITES
os.makedirs("png", exist_ok=True)
for k, (bb, _) in SITES.items():
    if len(sys.argv) > 1 and k not in sys.argv[1:]: continue
    z, dx, dy, meta = crop(*bb)
    save_png(z, dx, dy, f"png/{k}.png", meta=meta)
    print(k, z.shape, round(dx, 1), round(dy, 1), float(z.min()), float(z.max()))
