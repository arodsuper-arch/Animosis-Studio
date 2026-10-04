# Terrain sampling

Measures real landforms from Copernicus GLO-30 elevation tiles. Results and
method are written up in
[docs/terrain-reference/real-world-landforms.md](../../docs/terrain-reference/real-world-landforms.md).

```
pip install --user numpy scipy tifffile imagecodecs scikit-image pillow
python general.py        # slope and relief per site
python mounds.py         # also: lone_mountain.py walls.py transects.py basins.py dunes.py dunes_1d.py
```

Tiles download on first use into `tiles/` (~35 MB each, 15 tiles for the
default sites). Outputs go to `out/` and hillshade previews to `png/` via
`preview.py`. All three folders are gitignored.

To measure a new place, add a bounding box to `sites.py`.
