"""Manual cross-profiles across named features (endpoints in lat/lon).
Prints, for each side of the profile minimum (valley/fjord floor): rim height above floor, horizontal
distance floor->rim, mean wall slope, max 90 m-baseline slope.
Usage: python transects.py   (edit LINES)"""
import math
import numpy as np
from demlib import crop, latlon_to_rc, profile
from sites import SITES

LINES = {  # name: (site, (lat0, lon0), (lat1, lon1))
    "Geirangerfjord @7.06E": ("geiranger", (62.135, 7.06), (62.065, 7.06)),
    "Geirangerfjord @7.10E": ("geiranger", (62.140, 7.10), (62.070, 7.10)),
    "Geirangerfjord @7.15E": ("geiranger", (62.140, 7.15), (62.080, 7.15)),
    "Geirangerfjord @7.20E": ("geiranger", (62.135, 7.20), (62.075, 7.20)),
}


def analyse(site, a, b, rim_window_m=2500):
    z, dx, dy, meta = crop(*SITES[site][0])
    r0, c0 = latlon_to_rc(meta, *a); r1, c1 = latlon_to_rc(meta, *b)
    d, p = profile(z, dx, dy, r0, c0, r1, c1, step_m=15)
    i = int(np.argmin(p))
    out = dict(floor=float(p[i]))
    for side, sl in (("A", slice(max(0, i - int(rim_window_m / 15)), i + 1)), ("B", slice(i, i + int(rim_window_m / 15)))):
        seg, ds = p[sl], d[sl]
        j = int(np.argmax(seg)); h = seg[j] - p[i]; L = abs(ds[j] - d[i])
        g = np.degrees(np.arctan(np.abs((seg[6:] - seg[:-6]) / 90.0)))
        out[side] = dict(rim_h=float(h), run=float(L), mean_slope=math.degrees(math.atan(h / max(L, 1))), max90=float(g.max()))
    return out


if __name__ == "__main__":
    for k, (s, a, b) in LINES.items():
        r = analyse(s, a, b)
        print(k, "floor", round(r["floor"]), {sd: {kk: round(v, 1) for kk, v in r[sd].items()} for sd in "AB"})
