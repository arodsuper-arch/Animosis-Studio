"""Bluff (one-sided steep face) and Border-Wall (two-sided ridge) metrics.

BLUFFS - automatic steep-face extraction
  face mask = slope (of 1-px gaussian-smoothed DEM) >= FACE_DEG, binary-closed, components >= MIN_LEN long.
  Per face (PCA frame: u = along-face, v = across-face):
    length      = p98 - p2 of u
    face height = median over 60 m along-face bins of (max - min z) of the face dilated by 2 px
    face slope  = mean / p90 slope inside the face
    lobes       = along-face undulation of the face's planform: per 60 m bin, the mean v (offset)
                  -> quadratic detrend (removes overall bend) -> amplitude (p95-p5) and wavelength
                  = 2 * length / number of zero crossings, faces >= 1 km only.
  NOTE detection floor: a 40 deg face must span >= ~3-4 px (90-120 m horizontal) to survive, so faces
  lower than ~100 m are systematically missed at 30 m resolution.
    back slope  = mean slope of the ring 1..10 px outside the face whose z > face p90 (the top side)
    foot slope  = same, z < face p10
BORDER WALLS - automatic ridge extraction
  ridge mask = z - gaussian(z, sigma=TPI_SIGMA m) >= TPI_MIN, skeletonised; skeleton components >= 1 km.
  Per skeleton component: length (8-conn path length approx), crest roughness = std and p95-p5 of crest z after
  removing a 1 km running median along the PCA axis.
  Cross-sections every ~150 m along skeleton, perpendicular to local ridge direction (PCA of skeleton px within
  200 m), +-XS_HALF metres:
    side drop hA,hB  = crest - min(z) on each side; wall height = mean(hA,hB); skew = |hA-hB|/(hA+hB)
    side slope       = atan(h / distance to that minimum) (mean flank) and max slope within 300 m of crest
    crest width      = width of the contiguous part of the profile within 25 m of the crest (sharpness;
                       30 m pixels -> minimum resolvable ~ 30-60 m)
"""
import json, math, sys
import numpy as np
from scipy import ndimage as ndi
from skimage.morphology import skeletonize
from demlib import crop, slope_deg, pct, bilinear, rc_to_latlon
from sites import SITES

FACE_DEG = 40.0
MIN_LEN = 300.0


def pca_frame(x, y):
    X = np.c_[x - x.mean(), y - y.mean()]
    w, v = np.linalg.eigh(np.cov(X.T))
    a = v[:, 1]
    return X @ a, X @ np.array([-a[1], a[0]]), a


def bluffs(site):
    z, dx, dy, meta = crop(*SITES[site][0])
    s = slope_deg(ndi.gaussian_filter(z, 1), dx, dy)
    sraw = slope_deg(z, dx, dy)
    m = ndi.binary_closing(s >= FACE_DEG, np.ones((3, 3)))
    lab, n = ndi.label(m, np.ones((3, 3)))
    objs = ndi.find_objects(lab)
    out = []
    for i, sl in enumerate(objs, 1):
        pad = 12
        r0, r1 = max(0, sl[0].start - pad), min(z.shape[0], sl[0].stop + pad)
        c0, c1 = max(0, sl[1].start - pad), min(z.shape[1], sl[1].stop + pad)
        comp = lab[r0:r1, c0:c1] == i
        if comp.sum() < 15:
            continue
        rr, cc = np.nonzero(comp)
        u, v, a = pca_frame(cc * dx, rr * dy)
        L = np.percentile(u, 98) - np.percentile(u, 2)
        if L < MIN_LEN:
            continue
        zz = z[r0:r1, c0:c1]
        dil = ndi.binary_dilation(comp, iterations=2)
        dr, dc = np.nonzero(dil)
        ud, _, _ = pca_frame(dc * dx, dr * dy)
        ud = ud - (ud.mean() - u.mean()) if False else ud
        zd = zz[dil]
        bins = np.floor((ud - ud.min()) / 60).astype(int)
        hs = [np.ptp(zd[bins == b]) for b in np.unique(bins) if (bins == b).sum() >= 3]
        Hf = float(np.median(hs))
        sf = sraw[r0:r1, c0:c1][comp]
        ring = ndi.binary_dilation(comp, iterations=10) & ~ndi.binary_dilation(comp, iterations=1)
        zc = zz[comp]
        top = ring & (zz > np.percentile(zc, 90))
        bot = ring & (zz < np.percentile(zc, 10))
        ss = sraw[r0:r1, c0:c1]
        rec = dict(L=float(L), H=Hf, slope_mean=float(sf.mean()), slope_p90=float(np.percentile(sf, 90)),
                   back_slope=float(ss[top].mean()) if top.any() else None,
                   foot_slope=float(ss[bot].mean()) if bot.any() else None,
                   lat_lon=rc_to_latlon(meta, r0 + rr.mean(), c0 + cc.mean()))
        if L >= 1000:
            b = np.floor((u - u.min()) / 60).astype(int)
            off = np.array([v[b == k].mean() for k in range(b.max() + 1) if (b == k).any()])
            t = np.arange(off.size)
            off = off - np.polyval(np.polyfit(t, off, 2), t)  # quadratic: removes overall bend of the face
            rec["lobe_amp_p2p"] = float(np.percentile(off, 95) - np.percentile(off, 5))
            zc_ = np.count_nonzero(np.diff(np.sign(off)) != 0)
            rec["lobe_wavelength"] = float(2 * off.size * 60.0 / zc_) if zc_ >= 2 else None
        out.append(rec)
    return out


def walls(site, TPI_SIGMA=500.0, TPI_MIN=60.0, XS_HALF=1500.0):
    z, dx, dy, meta = crop(*SITES[site][0])
    sraw = slope_deg(z, dx, dy)
    tpi = z - ndi.gaussian_filter(z, (TPI_SIGMA / dy, TPI_SIGMA / dx))
    sk = skeletonize(ndi.binary_opening(tpi >= TPI_MIN))
    lab, n = ndi.label(sk, np.ones((3, 3)))
    px = 0.5 * (dx + dy)
    comps, xs = [], []
    for i in range(1, n + 1):
        rr, cc = np.nonzero(lab == i)
        if rr.size * px * 1.1 < 1000:
            continue
        u, v, a = pca_frame(cc * dx, rr * dy)
        o = np.argsort(u)
        zc = z[rr, cc][o]
        us = u[o]
        win = max(3, int(1000 / px))
        med = ndi.median_filter(zc, size=win, mode="nearest")
        res = zc - med
        comps.append(dict(length=float(rr.size * px * 1.1), straight_len=float(np.ptp(u)),
                          crest_mean=float(zc.mean()), rough_std=float(res.std()),
                          rough_p2p=float(np.percentile(res, 95) - np.percentile(res, 5)),
                          crest_range=float(np.ptp(zc)), lat_lon=rc_to_latlon(meta, rr.mean(), cc.mean())))
        # cross-sections
        pts = np.c_[cc * dx, rr * dy]
        stride = max(1, int(150 / px))
        for j in range(0, rr.size, stride):
            d = np.hypot(*(pts - pts[j]).T)
            nb = pts[d < 200]
            if len(nb) < 4:
                continue
            _, _, ax = pca_frame(nb[:, 0], nb[:, 1])
            nx, ny = -ax[1], ax[0]  # unit normal in metres (x east, y south since rows grow southward)
            t = np.arange(-XS_HALF, XS_HALF + 1, 15.0)
            prof = bilinear(z, rr[j] + t * ny / dy, cc[j] + t * nx / dx)
            ci = np.argmax(np.where(np.abs(t) <= 150, prof, -np.inf))
            zc0 = prof[ci]
            A, B = prof[:ci], prof[ci + 1:]
            if A.size < 20 or B.size < 20:
                continue
            ia, ib = np.argmin(A), np.argmin(B)
            hA, hB = zc0 - A[ia], zc0 - B[ib]
            dA, dB = abs(t[ci] - t[ia]), abs(t[ci + 1 + ib] - t[ci])
            g = np.degrees(np.arctan(np.abs(np.gradient(prof, 15.0))))
            near = np.abs(t - t[ci]) <= 300
            sideA = near & (t < t[ci]); sideB = near & (t > t[ci])
            within = prof >= zc0 - 25
            lo = ci
            while lo > 0 and within[lo - 1]:
                lo -= 1
            hi = ci
            while hi < len(t) - 1 and within[hi + 1]:
                hi += 1
            xs.append(dict(hA=float(max(hA, hB)), hB=float(max(0.0, min(hA, hB))), H=float(0.5 * (hA + hB)),
                           skew=float(abs(hA - hB) / (hA + hB + 1e-6)),
                           flank_steep=float(np.degrees(np.arctan(max(hA / dA, hB / dB)))),
                           flank_gentle=float(np.degrees(np.arctan(max(0.0, min(hA / dA, hB / dB))))),
                           max_slope_steep=float(max(g[sideA].max(), g[sideB].max())),
                           max_slope_gentle=float(min(g[sideA].max(), g[sideB].max())),
                           crest_w25=float((hi - lo + 1) * 15.0)))
    return comps, xs


if __name__ == "__main__":
    B = {}
    for s in (sys.argv[1:] or ["geiranger", "dolomites", "uluru", "zhangjiajie", "yangshuo", "kata_tjuta", "aso"]):
        f = bluffs(s)
        B[s] = f
        print(f"\n== BLUFFS {s}: n={len(f)} (len>=1km: {sum(q['L'] >= 1000 for q in f)})")
        for k in ("L", "H", "slope_mean", "slope_p90", "back_slope", "foot_slope", "lobe_amp_p2p", "lobe_wavelength"):
            vals = [q[k] for q in f if q.get(k) is not None]
            if vals:
                print(f"  {k:16s}", {p: round(v, 1) for p, v in pct(vals, (10, 50, 90, 100)).items()})
    W = {}
    for s in ["dolomites", "geiranger", "zhangjiajie", "aso", "yangshuo"]:
        comps, xs = walls(s)
        W[s] = dict(comps=comps, xs=xs)
        print(f"\n== WALLS {s}: ridges={len(comps)} cross-sections={len(xs)}")
        for k in ("length", "straight_len", "rough_std", "rough_p2p", "crest_range"):
            print(f"  {k:16s}", {p: round(v, 1) for p, v in pct([c[k] for c in comps], (10, 50, 90, 100)).items()})
        for k in ("H", "hA", "hB", "skew", "flank_steep", "flank_gentle", "max_slope_steep", "max_slope_gentle", "crest_w25"):
            print(f"  {k:16s}", {p: round(v, 2) for p, v in pct([c[k] for c in xs], (10, 50, 90, 99)).items()})
        for c in sorted(comps, key=lambda c: -c["length"])[:3]:
            print("   longest", {k: (round(v, 1) if isinstance(v, float) else tuple(round(x, 3) for x in v)) for k, v in c.items()})
    json.dump(dict(bluffs=B, walls=W), open("out/walls.json", "w"), default=float)
