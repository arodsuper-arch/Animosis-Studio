"""Shared helpers for measuring landforms on Copernicus GLO-30 tiles.

Conventions
-----------
* Arrays are row 0 = north. z in metres (EGM2008 heights, DSM - includes canopy/buildings).
* dx (east-west pixel size, m) = deg_x * 111320 * cos(lat); dy = deg_y * 110574.
  GLO-30 lon spacing widens above 50 deg lat (1.5"/2"/3"...) - read from tile tags.
"""
import os, math, heapq
import numpy as np
import tifffile
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
TILES = os.path.join(HERE, "tiles")
M_PER_DEG_LAT = 110574.0
M_PER_DEG_LON_EQ = 111320.0

_cache = {}


def tile_code(lat, lon):
    la, lo = math.floor(lat), math.floor(lon)
    return f"{'N' if la >= 0 else 'S'}{abs(la):02d}{'E' if lo >= 0 else 'W'}{abs(lo):03d}"


def load_tile(code):
    if code not in _cache:
        path = os.path.join(TILES, code + ".tif")
        if not os.path.exists(path):
            from download import fetch
            fetch(code, TILES)
        with tifffile.TiffFile(path) as t:
            p = t.pages[0]
            z = p.asarray().astype(np.float32)
            tie = p.tags["ModelTiepointTag"].value
            sc = p.tags["ModelPixelScaleTag"].value
        _cache[code] = (z, tie[3], tie[4], sc[0], sc[1])  # z, lon0, lat0(top), dlon, dlat
    return _cache[code]


def crop(lat_min, lat_max, lon_min, lon_max):
    """Return (z, dx_m, dy_m, meta). Mosaics across tile borders (same lat band)."""
    rows = []
    lat_tiles = range(math.floor(lat_max - 1e-9), math.floor(lat_min) - 1, -1)  # north -> south
    for la in lat_tiles:
        cols = []
        for lo in range(math.floor(lon_min), math.floor(lon_max - 1e-9) + 1):
            z, lon0, lat0, dlon, dlat = load_tile(tile_code(la + 0.5, lo + 0.5))
            a = max(lat_min, la); b = min(lat_max, la + 1)
            c = max(lon_min, lo); d = min(lon_max, lo + 1)
            r0 = int(round((lat0 - b) / dlat)); r1 = int(round((lat0 - a) / dlat))
            c0 = int(round((c - lon0) / dlon)); c1 = int(round((d - lon0) / dlon))
            cols.append(z[r0:r1, c0:c1])
        rows.append(np.hstack(cols))
    out = np.vstack(rows)
    latc = 0.5 * (lat_min + lat_max)
    dx = dlon * M_PER_DEG_LON_EQ * math.cos(math.radians(latc))
    dy = dlat * M_PER_DEG_LAT
    meta = dict(lat_max=lat_max, lon_min=lon_min, dlat=dlat, dlon=dlon)
    out = np.where(out < -1000, np.nan, out)
    if np.isnan(out).any():
        out = fill_nan(out)
    return out, dx, dy, meta


def fill_nan(z):
    m = np.isnan(z)
    idx = ndi.distance_transform_edt(m, return_distances=False, return_indices=True)
    return z[tuple(idx)]


def rc_to_latlon(meta, r, c):
    return meta["lat_max"] - (r + 0.5) * meta["dlat"], meta["lon_min"] + (c + 0.5) * meta["dlon"]


def latlon_to_rc(meta, lat, lon):
    return (meta["lat_max"] - lat) / meta["dlat"] - 0.5, (lon - meta["lon_min"]) / meta["dlon"] - 0.5


# ------------------------------------------------------------------ basic derivatives
def slope_deg(z, dx, dy):
    gy, gx = np.gradient(z, dy, dx)
    return np.degrees(np.arctan(np.hypot(gx, gy)))


def pct(a, ps=(5, 25, 50, 75, 90, 95, 99)):
    a = np.asarray(a).ravel()
    a = a[np.isfinite(a)]
    return {p: float(np.percentile(a, p)) for p in ps}


def local_relief(z, dx, dy, window_m):
    """max-min inside a window_m x window_m square (metres)."""
    ny = max(3, int(round(window_m / dy)) | 1)
    nx = max(3, int(round(window_m / dx)) | 1)
    return ndi.maximum_filter(z, size=(ny, nx)) - ndi.minimum_filter(z, size=(ny, nx))


def hillshade(z, dx, dy, az=315, alt=45):
    gy, gx = np.gradient(z, dy, dx)
    slope = np.arctan(np.hypot(gx, gy))
    aspect = np.arctan2(-gx, gy)
    azr, altr = np.radians(360 - az + 90), np.radians(alt)
    hs = np.sin(altr) * np.cos(slope) + np.cos(altr) * np.sin(slope) * np.cos(azr - aspect)
    return np.clip(hs, 0, 1)


def save_png(z, dx, dy, path, grid_km=None, meta=None):
    from PIL import Image
    hs = hillshade(z, dx, dy)
    zn = (z - np.nanpercentile(z, 1)) / (np.nanpercentile(z, 99) - np.nanpercentile(z, 1) + 1e-6)
    zn = np.clip(zn, 0, 1)
    rgb = np.stack([0.35 + 0.65 * zn, 0.55 + 0.25 * zn, 0.85 - 0.5 * zn], -1) * (0.35 + 0.65 * hs[..., None])
    img = (np.clip(rgb, 0, 1) * 255).astype(np.uint8)
    if meta is not None:  # labelled lat/lon graticule
        from PIL import ImageDraw
        im = Image.fromarray(img); dr = ImageDraw.Draw(im)
        h, w = img.shape[:2]
        span = max(h * meta["dlat"], w * meta["dlon"])
        step = 0.01 if span < 0.25 else 0.02 if span < 0.5 else 0.05
        lat_max, lon_min = meta["lat_max"], meta["lon_min"]
        lat = math.floor(lat_max / step) * step
        while True:
            r = int((lat_max - lat) / meta["dlat"])
            if r >= h: break
            if r >= 0:
                dr.line([(0, r), (w, r)], fill=(255, 0, 0)); dr.text((2, r + 1), f"{lat:.2f}", fill=(255, 255, 255))
            lat -= step
        lon = math.ceil(lon_min / step) * step
        while True:
            c = int((lon - lon_min) / meta["dlon"])
            if c >= w: break
            dr.line([(c, 0), (c, h)], fill=(255, 0, 0)); dr.text((c + 2, 2), f"{lon:.2f}", fill=(255, 255, 255))
            lon += step
        img = np.asarray(im)
    Image.fromarray(img).save(path)


# ------------------------------------------------------------------ peaks & prominence
def prominence_peaks(z, min_prom=5.0):
    """Exact (8-connected) topographic prominence via descending union-find.

    Returns list of dicts: r, c, z, prom, col_z, base_area_px (pixels in the peak's
    component at the moment it merges into higher ground = area above its key col).
    The global max gets prom = z - min(z) (edge-limited). Crop edges are treated as
    unknown, so peaks near the border may be under-estimated.
    """
    h, w = z.shape
    flat = z.ravel()
    order = np.argsort(-flat, kind="stable")
    parent = -np.ones(flat.size, dtype=np.int64)
    peak = np.zeros(flat.size, dtype=np.int64)    # root -> pixel of its highest point
    size = np.zeros(flat.size, dtype=np.int64)
    res = []

    def find(a):
        root = a
        while parent[root] != root:
            root = parent[root]
        while parent[a] != root:
            parent[a], a = root, parent[a]
        return root

    nb = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    for p in order:
        r, c = divmod(int(p), w)
        parent[p] = p; peak[p] = p; size[p] = 1
        roots = set()
        for dr, dc in nb:
            rr, cc = r + dr, c + dc
            if 0 <= rr < h and 0 <= cc < w:
                q = rr * w + cc
                if parent[q] >= 0:
                    roots.add(find(q))
        if not roots:
            continue
        roots = sorted(roots, key=lambda q: -flat[peak[q]])
        top = roots[0]
        for o in roots[1:]:
            pk = peak[o]
            prom = flat[pk] - flat[p]
            if prom >= min_prom:
                pr, pc = divmod(int(pk), w)
                res.append(dict(r=pr, c=pc, z=float(flat[pk]), prom=float(prom), col_z=float(flat[p]),
                                base_area_px=int(size[o])))
            parent[o] = top; size[top] += size[o]
        parent[p] = top; size[top] += 1
    g = int(order[0]); gr, gc = divmod(g, w)
    res.append(dict(r=gr, c=gc, z=float(flat[g]), prom=float(flat[g] - flat.min()), col_z=float(flat.min()),
                    base_area_px=int(flat.size), is_global=True))
    return res


def peak_region(z, pk, level=None):
    """Mask of pixels connected to the peak and above `level` (default its key col)."""
    level = pk["col_z"] if level is None else level
    lab, _ = ndi.label(z > level, structure=np.ones((3, 3)))
    return lab == lab[pk["r"], pk["c"]]


# ------------------------------------------------------------------ depressions
def priority_flood(z):
    """Barnes et al. priority-flood depression filling (edges drain). Returns filled DEM."""
    h, w = z.shape
    filled = z.astype(np.float64).copy()
    seen = np.zeros((h, w), bool)
    pq = []
    for r in range(h):
        for c in (0, w - 1):
            heapq.heappush(pq, (filled[r, c], r, c)); seen[r, c] = True
    for c in range(1, w - 1):
        for r in (0, h - 1):
            heapq.heappush(pq, (filled[r, c], r, c)); seen[r, c] = True
    nb = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    while pq:
        v, r, c = heapq.heappop(pq)
        for dr, dc in nb:
            rr, cc = r + dr, c + dc
            if 0 <= rr < h and 0 <= cc < w and not seen[rr, cc]:
                seen[rr, cc] = True
                if filled[rr, cc] < v:
                    filled[rr, cc] = v
                heapq.heappush(pq, (filled[rr, cc], rr, cc))
    return filled


# ------------------------------------------------------------------ sampling
def bilinear(z, rows, cols):
    return ndi.map_coordinates(z, [rows, cols], order=1, mode="nearest")


def profile(z, dx, dy, r0, c0, r1, c1, step_m=None):
    """Sample a straight profile; returns (dist_m, z)."""
    L = math.hypot((r1 - r0) * dy, (c1 - c0) * dx)
    step_m = step_m or min(dx, dy)
    n = max(2, int(L / step_m) + 1)
    t = np.linspace(0, 1, n)
    return t * L, bilinear(z, r0 + t * (r1 - r0), c0 + t * (c1 - c0))


def summary_block(name, z, dx, dy):
    s = slope_deg(z, dx, dy)
    out = {"site": name, "shape": z.shape, "dx": dx, "dy": dy,
           "elev": pct(z, (1, 50, 99)), "slope": pct(s)}
    for wm in (100, 500, 1000):
        out[f"relief{wm}"] = pct(local_relief(z, dx, dy, wm), (10, 50, 90, 99))
    return out
