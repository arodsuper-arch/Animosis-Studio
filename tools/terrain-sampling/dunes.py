"""Dune wavelength / height.

1) Resample crop to isotropic 30 m grid; remove regional trend with a Gaussian high-pass (sigma = HP m).
2) 2-D FFT (Hann window) -> power spectrum; the dominant wavenumber (excluding wavelengths > MAXL)
   gives crest spacing and the crest-normal direction. Also reports the power-weighted median wavelength.
3) Cross-check: autocorrelation of the detrended field along the dominant direction -> first peak lag.
4) Heights: profiles sampled along the dominant direction every 300 m across the crop; crests/troughs via
   find_peaks(distance >= 0.5 lambda, prominence >= 2 m) on the *non*-high-passed profile;
   dune height = crest - mean(adjacent troughs).
5) Superimposed small dunes: spectral peak restricted to 150-800 m and p95-p5 of a sigma=150 m high-pass.
Note: 30 m posting -> dunes with spacing < ~150 m (5 px/cycle) are not measurable; slip faces
(~30-34 deg in reality) are smoothed to lower slopes in GLO-30.
"""
import json, math, sys
import numpy as np
from scipy import ndimage as ndi
from scipy.signal import find_peaks
from demlib import crop, pct, bilinear

PX = 30.0


def iso(z, dx, dy):
    return ndi.zoom(z, (dy / PX, dx / PX), order=1)


def measure(site, HP=4000.0, MAXL=6000.0):
    z, dx, dy, meta = crop(*__import__("sites").SITES[site][0])
    z = iso(z, dx, dy)
    hp = z - ndi.gaussian_filter(z, HP / PX)
    h, w = hp.shape
    win = np.outer(np.hanning(h), np.hanning(w))
    F = np.abs(np.fft.fftshift(np.fft.fft2(hp * win))) ** 2
    ky = np.fft.fftshift(np.fft.fftfreq(h, PX)); kx = np.fft.fftshift(np.fft.fftfreq(w, PX))
    KX, KY = np.meshgrid(kx, ky)
    K = np.hypot(KX, KY)
    valid = (K > 1 / MAXL) & (K < 1 / (5 * PX))
    Fs = ndi.gaussian_filter(np.where(valid, F, 0), 1.5)
    i = np.argmax(Fs)
    kpk = K.flat[i]
    lam = 1 / kpk
    theta = math.degrees(math.atan2(-KY.flat[i], KX.flat[i])) % 180  # direction of wave vector (deg from east, CCW)
    wl = 1 / K[valid]; pw = F[valid]
    o = np.argsort(wl); cw = np.cumsum(pw[o]) / pw.sum()
    lam_med = wl[o][np.searchsorted(cw, 0.5)]
    # autocorrelation along dominant direction
    ac = np.fft.ifft2(np.abs(np.fft.fft2(hp - hp.mean())) ** 2).real
    ac = np.fft.fftshift(ac) / ac.max() if False else np.fft.fftshift(ac / ac.flat[0])
    cy, cx = h // 2, w // 2
    ux, uy = KX.flat[i] / kpk, KY.flat[i] / kpk  # unit wave vector (x east, y = row direction)
    t = np.arange(0, min(MAXL, 0.45 * min(h, w) * PX), PX)
    acp = bilinear(ac, cy + t * uy / PX, cx + t * ux / PX)
    pk, _ = find_peaks(acp)
    lam_ac = float(t[pk[0]]) if pk.size else None
    # heights along profiles parallel to the wave vector
    heights, spac = [], []
    nx_, ny_ = -uy, ux
    L = 1.0 * max(h, w) * PX
    s = np.arange(-L / 2, L / 2, PX)
    for off in np.arange(-L / 2, L / 2, 300.0):
        rr = cy + (s * uy + off * ny_) / PX; cc = cx + (s * ux + off * nx_) / PX
        ok = (rr >= 0) & (rr < h - 1) & (cc >= 0) & (cc < w - 1)
        if ok.sum() < 3 * lam / PX:
            continue
        p = bilinear(z, rr[ok], cc[ok])
        pc, _ = find_peaks(p, distance=max(2, int(0.5 * lam / PX)), prominence=2)
        tr, _ = find_peaks(-p, distance=max(2, int(0.5 * lam / PX)), prominence=2)
        for a in pc:
            l = tr[tr < a]; r = tr[tr > a]
            if l.size and r.size:
                heights.append(p[a] - 0.5 * (p[l[-1]] + p[r[0]]))
        if pc.size > 1:
            spac.extend(np.diff(pc) * PX)
    # superimposed small dunes: spectral peak in 150..800 m band, amplitude of sigma=150 m high-pass
    vs = (K > 1 / 800.0) & (K < 1 / 150.0)
    j = np.argmax(np.where(vs, Fs, 0))
    hp_s = z - ndi.gaussian_filter(z, 150.0 / PX)
    small = dict(lambda_small=float(1 / K.flat[j]), amp_p95_p5=float(np.percentile(hp_s, 95) - np.percentile(hp_s, 5)))
    from demlib import slope_deg
    sl = slope_deg(z, PX, PX)
    return dict(site=site, lambda_fft=float(lam), lambda_powmedian=float(lam_med), lambda_autocorr=lam_ac,
                wavevector_deg_from_E=float(theta), crest_spacing_profiles=pct(spac, (10, 25, 50, 75, 90)) if spac else None,
                height=pct(heights, (10, 25, 50, 75, 90, 99)) if heights else None, n_dunes=len(heights),
                hp_rms=float(hp.std()), superimposed=small, slope=pct(sl, (50, 90, 99)))


if __name__ == "__main__":
    res = {}
    for s in (sys.argv[1:] or ["liwa", "namib", "namib_south", "rub_al_khali"]):
        res[s] = measure(s)
        print(json.dumps(res[s], indent=1, default=float))
    json.dump(res, open("out/dunes.json", "w"), default=float)
