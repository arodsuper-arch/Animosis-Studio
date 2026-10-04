"""Download Copernicus GLO-30 DEM tiles (public AWS bucket, no auth).
Usage: python download.py N29E110 N24E110 ...   (tile = lower-left corner)"""
import sys, os, re, urllib.request
BASE = "https://copernicus-dem-30m.s3.amazonaws.com"
def tile_name(code):
    m = re.match(r"([NS])(\d+)([EW])(\d+)", code)
    ns, la, ew, lo = m.groups()
    return f"Copernicus_DSM_COG_10_{ns}{int(la):02d}_00_{ew}{int(lo):03d}_00_DEM"
def fetch(code, outdir="tiles"):
    os.makedirs(outdir, exist_ok=True)
    n = tile_name(code); out = os.path.join(outdir, code + ".tif")
    if os.path.exists(out) and os.path.getsize(out) > 1e6: return out
    url = f"{BASE}/{n}/{n}.tif"
    print("GET", url, flush=True)
    urllib.request.urlretrieve(url, out)
    return out
if __name__ == "__main__":
    for c in sys.argv[1:]:
        try: print(fetch(c), os.path.getsize(fetch(c)))
        except Exception as e: print(c, "FAILED", e)
