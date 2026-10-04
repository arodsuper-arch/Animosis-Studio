"""Lone Mountain metrics from radial profiles around the summit.

* summit = max of a lightly smoothed DEM inside the crop
* 180 radial profiles (2 deg) out to R_MAX, step 30 m
* base elevation = median over azimuths of the profile minimum beyond 0.7*R_MAX
  (i.e. the surrounding plain/ring); height H = summit - base
* base radius per azimuth = first radius where profile <= base + 5% H; base width = 2 * median radius
* normalised profile z/H vs r/R -> concavity (value at r/R = 0.5; straight cone = 0.5, concave < 0.5)
* slope by elevation band: mean along-profile slope in top 10% / mid / bottom 30% of H
* summit curvature: fit z = z0 - r^2/(2 Rc) to points within SUMMIT_R -> radius of curvature Rc
* radial ridges / gullies: residual = z - azimuthal mean at fixed radius; count maxima of residual vs
  azimuth with prominence >= RID_PROM (scipy.signal.find_peaks); gully depth = prominence of minima
"""
import json, math, sys
import numpy as np
from scipy import ndimage as ndi
from scipy.signal import find_peaks
from demlib import crop, bilinear, pct
from sites import SITES

CFG = {"fuji": dict(R_MAX=22000, SUMMIT_R=600, RID_PROM=5),
       "uluru": dict(R_MAX=5000, SUMMIT_R=300, RID_PROM=3),
       "kata_tjuta": dict(R_MAX=4000, SUMMIT_R=200, RID_PROM=5)}


def measure(site, R_MAX, SUMMIT_R, RID_PROM):
    z, dx, dy, meta = crop(*SITES[site][0])
    zs = ndi.gaussian_filter(z, 1)
    r0, c0 = np.unravel_index(np.argmax(zs), z.shape)
    step = 30.0
    rr = np.arange(0, R_MAX + step, step)
    az = np.radians(np.arange(0, 360, 2.0))
    P = np.empty((az.size, rr.size))
    for i, a in enumerate(az):
        P[i] = bilinear(z, r0 - rr * np.cos(a) / dy, c0 + rr * np.sin(a) / dx)  # a=0 -> north
    zt = float(z[r0, c0])
    base = float(np.median(P[:, rr >= 0.7 * R_MAX].min(1)))
    H = zt - base
    Rb = np.array([rr[np.argmax(p <= base + 0.05 * H)] if (p <= base + 0.05 * H).any() else np.nan for p in P])
    R = float(np.nanmedian(Rb))
    # normalised mean profile
    rn = np.linspace(0, 1, 21)
    prof = np.array([np.interp(rn * Rb[i], rr, P[i]) for i in range(len(az)) if np.isfinite(Rb[i])])
    zn = (np.median(prof, 0) - base) / H
    # slope by elevation band (along-profile)
    sl = np.degrees(np.arctan(np.abs(np.gradient(P, step, axis=1))))
    rel = (P - base) / H
    inside = rr[None, :] <= Rb[:, None]
    band = lambda lo, hi: float(np.median(sl[inside & (rel >= lo) & (rel < hi)]))
    # summit curvature
    m = rr <= SUMMIT_R
    A = np.vstack([np.ones(m.sum() * len(az)), -np.tile(rr[m] ** 2, len(az))]).T
    coef = np.linalg.lstsq(A, P[:, m].ravel(), rcond=None)[0]
    Rc = 1 / (2 * coef[1]) if coef[1] > 0 else float("inf")
    # ridges / gullies
    rid = {}
    for f in (0.3, 0.5, 0.7):
        k = int(round(f * R / step))
        az_f = np.radians(np.arange(0, 360, 0.5))
        ring = bilinear(z, r0 - rr[k] * np.cos(az_f) / dy, c0 + rr[k] * np.sin(az_f) / dx)
        res = ring - ring.mean()
        res3 = np.concatenate([res, res, res])
        pk, pp = find_peaks(res3, prominence=RID_PROM)
        tr, tp = find_peaks(-res3, prominence=RID_PROM)
        sel = (pk >= res.size) & (pk < 2 * res.size)
        selt = (tr >= res.size) & (tr < 2 * res.size)
        circ = 2 * math.pi * rr[k]
        rid[f] = dict(r_m=float(rr[k]), n_ridges=int(sel.sum()),
                      gully_depth=pct(tp["prominences"][selt], (25, 50, 90)) if selt.any() else None,
                      ridge_spacing_m=circ / max(1, sel.sum()))
    return dict(site=site, summit=dict(r=int(r0), c=int(c0), z=zt), base_z=base, H=H, base_width=2 * R,
                base_radius_pct=pct(Rb, (10, 50, 90)), aspect_H_over_W=H / (2 * R),
                mean_slope_overall=math.degrees(math.atan(H / R)),
                norm_profile={f"{a:.2f}": round(float(b), 3) for a, b in zip(rn, zn)},
                slope_top10=band(0.9, 1.01), slope_mid=band(0.3, 0.9), slope_bottom30=band(0.0, 0.3),
                summit_curv_radius_m=Rc, ridges=rid)


if __name__ == "__main__":
    sites = sys.argv[1:] or list(CFG)
    res = {s: measure(s, **CFG[s]) for s in sites}
    json.dump(res, open("out/lone_mountain.json", "w"), indent=1, default=float)
    print(json.dumps(res, indent=1, default=float))
