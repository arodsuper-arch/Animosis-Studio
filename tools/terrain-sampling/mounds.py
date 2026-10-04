"""Mound / tower / pillar-cluster metrics.

For every peak with prominence >= MIN_PROM (exact 8-connected prominence, demlib.prominence_peaks):
  H_local1k   = peak minus minimum elevation inside a 1 km square window (relief above local base)
  height      = prominence (m)  (= relief above the key col; for a tower on a plain this is relief above the plain)
  footprint   = equivalent diameter 2*sqrt(A/pi) of the region connected to the peak and above
                col + 10% of prominence (A capped at the peak's own basin, so neighbours are excluded)
  steepness   = mean and p90 slope inside that footprint; H/D aspect ratio
Spacing      = nearest-neighbour distance between peaks (m)
Clusters     = single-linkage groups with link distance = CLUSTER_K * median NN distance -> members per cluster
Peaks touching the crop border (within 3 px) are dropped.
"""
import json, sys
import numpy as np
from scipy import ndimage as ndi
from scipy.spatial import cKDTree
from scipy.cluster.hierarchy import fcluster, linkage
from demlib import crop, prominence_peaks, slope_deg, pct
from sites import SITES

CFG = {  # site: (min prominence m, max footprint diameter m to count as a "mound")
    "zhangjiajie": (20, 1500),
    "yangshuo": (20, 1500),
    "chocolate": (10, 1500),
    "kata_tjuta": (20, 2500),
}
CLUSTER_K = 1.5


def measure(site, min_prom, max_d):
    z, dx, dy, meta = crop(*SITES[site][0])
    s = slope_deg(z, dx, dy)
    pk = prominence_peaks(z, min_prom)  # global max kept (prom = z - crop min) unless on border
    h, w = z.shape
    zmin1k = ndi.minimum_filter(z, size=(int(1000 / dy) | 1, int(1000 / dx) | 1))
    rows = []
    for p in pk:
        if p["r"] < 3 or p["c"] < 3 or p["r"] > h - 4 or p["c"] > w - 4:
            continue
        lvl = p["col_z"] + 0.1 * p["prom"]
        r0, r1 = max(0, p["r"] - 120), min(h, p["r"] + 121)
        c0, c1 = max(0, p["c"] - 120), min(w, p["c"] + 121)
        sub = z[r0:r1, c0:c1]
        lab, _ = ndi.label(sub > lvl, structure=np.ones((3, 3)))
        m = lab == lab[p["r"] - r0, p["c"] - c0]
        area = m.sum() * dx * dy
        D = 2 * np.sqrt(area / np.pi)
        if D > max_d:
            continue
        ss = s[r0:r1, c0:c1][m]
        rows.append(dict(r=p["r"], c=p["c"], H=p["prom"], H_local1k=float(z[p["r"], p["c"]] - zmin1k[p["r"], p["c"]]), D=D, slope_mean=float(ss.mean()),
                         slope_p90=float(np.percentile(ss, 90)), HD=p["prom"] / D))
    xy = np.array([[q["c"] * dx, q["r"] * dy] for q in rows])
    nn = cKDTree(xy).query(xy, 2)[0][:, 1]
    link = CLUSTER_K * np.median(nn)
    lab = fcluster(linkage(xy, "single"), link, "distance")
    sizes = np.bincount(lab)[1:]
    sizes = sizes[sizes >= 2]
    area_km2 = z.size * dx * dy / 1e6
    out = dict(site=site, n=len(rows), density_per_km2=len(rows) / area_km2,
               H=pct([q["H"] for q in rows]), H_local1k=pct([q["H_local1k"] for q in rows]), D=pct([q["D"] for q in rows]),
               slope_mean=pct([q["slope_mean"] for q in rows]), slope_p90=pct([q["slope_p90"] for q in rows]),
               HD=pct([q["HD"] for q in rows]), nn=pct(nn), cluster_link_m=float(link),
               cluster_sizes=pct(sizes, (10, 50, 90, 100)), n_clusters=int(len(sizes)),
               top5=sorted(rows, key=lambda q: -q["H"])[:5])
    return out


if __name__ == "__main__":
    sites = sys.argv[1:] or list(CFG)
    res = {s: measure(s, *CFG[s]) for s in sites}
    json.dump(res, open("out/mounds.json", "w"), indent=1)
    for s, r in res.items():
        print(f"\n== {s}: n={r['n']} density={r['density_per_km2']:.1f}/km2 clusters={r['n_clusters']} link={r['cluster_link_m']:.0f} m")
        for k in ("H", "H_local1k", "D", "HD", "slope_mean", "slope_p90", "nn", "cluster_sizes"):
            print(f"  {k:12s}", {p: round(v, 2) for p, v in r[k].items()})
        for q in r["top5"]:
            print("   top", {k: round(v, 2) for k, v in q.items()})
