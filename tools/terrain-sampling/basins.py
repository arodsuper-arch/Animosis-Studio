"""Basin metrics.

1) Caldera (Aso): rays every 2 deg from a hand-picked centre; rim = max z along the ray within
   [R_IN, R_OUT]; rim radius & height per ray. Interior = polygon of rim points.
   depth = median(rim z) - floor (p2 of interior z); width = 2 * median rim radius (also min/max diameters).
   floor flatness = fraction of interior area with z <= floor + f * depth for f = 0.1, 0.25.
   Lowest rim point = spill point (outlet gorge).
2) Closed depressions anywhere (priority-flood fill, Barnes 2014; crop edges drain):
   depth map = filled - z, regions with depth > 0.5 m (8-conn); keep max depth >= MIN_DEPTH and >= 10 px.
   per depression: equivalent diameter, max depth, depth/width, flatness = fraction of its area with
   z <= min + 0.1 * maxdepth (and 0.25).
   DSM caveat: canopy/buildings/noise create shallow fake pits -> MIN_DEPTH filter.
"""
import json, math, sys
import numpy as np
from scipy import ndimage as ndi
from skimage.draw import polygon as draw_polygon
from demlib import crop, latlon_to_rc, bilinear, priority_flood, pct
from sites import SITES


def caldera(site="aso", center=(32.898, 131.072), R_IN=6000, R_OUT=16000):
    z, dx, dy, meta = crop(*SITES[site][0])
    r0, c0 = latlon_to_rc(meta, *center)
    rr = np.arange(0, R_OUT + 30, 30.0)
    az = np.radians(np.arange(0, 360, 2.0))
    rim_r, rim_z, poly = [], [], []
    for a in az:
        p = bilinear(z, r0 - rr * np.cos(a) / dy, c0 + rr * np.sin(a) / dx)
        m = rr >= R_IN
        k = np.argmax(np.where(m, p, -np.inf))
        rim_r.append(rr[k]); rim_z.append(p[k])
        poly.append((c0 + rr[k] * np.sin(a) / dx, r0 - rr[k] * np.cos(a) / dy))
    rim_r, rim_z = np.array(rim_r), np.array(rim_z)
    inside = np.zeros(z.shape, bool)
    pr, pc = draw_polygon([p[1] for p in poly], [p[0] for p in poly], z.shape)
    inside[pr, pc] = True
    zi = z[inside]
    floor = float(np.percentile(zi, 2))
    depth = float(np.median(rim_z) - floor)
    diam = rim_r[: len(az) // 2] + rim_r[len(az) // 2:]
    return dict(site=site, rim_z=pct(rim_z, (0, 10, 50, 90, 100)), floor=floor, depth=depth,
                depth_at_spill=float(rim_z.min() - floor),
                width_median=float(2 * np.median(rim_r)), diam_min=float(diam.min()), diam_max=float(diam.max()),
                area_km2=float(inside.sum() * dx * dy / 1e6),
                flat10=float(np.mean(zi <= floor + 0.1 * depth)), flat25=float(np.mean(zi <= floor + 0.25 * depth)),
                interior_slope_note="central cones included")


def depressions(site, MIN_DEPTH=5.0):
    z, dx, dy, meta = crop(*SITES[site][0])
    f = priority_flood(z)
    d = f - z
    lab, n = ndi.label(d > 0.5, np.ones((3, 3)))
    out = []
    for i, sl in enumerate(ndi.find_objects(lab), 1):
        m = lab[sl] == i
        if m.sum() < 10:
            continue
        dd = d[sl][m]
        D = float(dd.max())
        if D < MIN_DEPTH:
            continue
        zz = z[sl][m]
        A = m.sum() * dx * dy
        W = 2 * math.sqrt(A / math.pi)
        out.append(dict(W=W, D=D, DW=D / W, flat10=float(np.mean(zz <= zz.min() + 0.1 * D)),
                        flat25=float(np.mean(zz <= zz.min() + 0.25 * D))))
    return out


if __name__ == "__main__":
    c = caldera()
    print("CALDERA", json.dumps(c, indent=1))
    res = {"aso_caldera": c}
    for s in (sys.argv[1:] or ["yangshuo", "chocolate", "liwa", "namib", "zhangjiajie"]):
        dep = depressions(s)
        res[s] = dep
        print(f"\n== depressions {s}: n={len(dep)}")
        if dep:
            for k in ("W", "D", "DW", "flat10", "flat25"):
                print(f"  {k:7s}", {p: round(v, 3) for p, v in pct([q[k] for q in dep], (10, 50, 90, 100)).items()})
    json.dump(res, open("out/basins.json", "w"), default=float)
