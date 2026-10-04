"""Per-site slope distribution and local relief (100 m / 500 m / 1 km square windows).
Writes out/general.json and prints a markdown table."""
import json
from demlib import crop, summary_block
from sites import SITES
res = {}
for k, (bb, desc) in SITES.items():
    z, dx, dy, meta = crop(*bb)
    res[k] = summary_block(k, z, dx, dy); res[k]["desc"] = desc
json.dump(res, open("out/general.json", "w"), indent=1, default=str)
print("| site | px (m) | slope p50 | p90 | p99 | relief100 p50/p90 | relief500 p50/p90 | relief1k p50/p90 | elev p1-p99 |")
print("|---|---|---|---|---|---|---|---|---|")
for k, r in res.items():
    s = r["slope"]
    f = lambda key: f"{r[key][50]:.0f} / {r[key][90]:.0f}"
    print(f"| {k} | {r['dx']:.0f}x{r['dy']:.0f} | {s[50]:.1f} | {s[90]:.1f} | {s[99]:.1f} | {f('relief100')} | {f('relief500')} | {f('relief1000')} | {r['elev'][1]:.0f}-{r['elev'][99]:.0f} |")
