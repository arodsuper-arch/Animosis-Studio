"""1-D check for linear dunes of known orientation: mean periodogram of E-W rows (high-passed, Hann),
plus crest-to-adjacent-trough heights along every 10th row. Usage: python dunes_1d.py namib_south"""
import sys
import numpy as np
from scipy import ndimage as ndi
from scipy.signal import find_peaks
from demlib import crop, pct
from sites import SITES
from dunes import iso, PX
site = sys.argv[1] if len(sys.argv) > 1 else "namib_south"
z, dx, dy, meta = crop(*SITES[site][0]); z = iso(z, dx, dy)
hp = z - ndi.gaussian_filter(z, 4000 / PX)
w = z.shape[1]
P = np.mean(np.abs(np.fft.rfft(hp * np.hanning(w), axis=1)) ** 2, 0)
f = np.fft.rfftfreq(w, PX)
ok = (f > 1 / 6000) & (f < 1 / 150)
k = np.argmax(np.where(ok, ndi.gaussian_filter1d(P, 1), 0))
print(site, "row-spectrum peak wavelength", round(1 / f[k]), "m")
H, S = [], []
for r in range(0, z.shape[0], 10):
    p = z[r]
    pc, _ = find_peaks(p, distance=int(0.5 / f[k] / PX), prominence=5)
    tr, _ = find_peaks(-p, distance=int(0.5 / f[k] / PX), prominence=5)
    S.extend(np.diff(pc) * PX)
    for a in pc:
        l = tr[tr < a]; rr = tr[tr > a]
        if l.size and rr.size: H.append(p[a] - 0.5 * (p[l[-1]] + p[rr[0]]))
print("spacing", {k_: round(v) for k_, v in pct(S, (10, 50, 90)).items()}, "height", {k_: round(v) for k_, v in pct(H, (10, 50, 90, 99)).items()}, len(H))
