"""Generates the paper and wood tiles for the classic library skins.

Generated rather than downloaded so there is no licence to track, and so the
result can be reproduced or tuned from here. Both tiles repeat seamlessly:
every noise layer is built on a periodic grid, so the right edge continues the
left one and the bottom continues the top.

    python tools/skins/generar_texturas.py

Writes assets/skins/parchment.png and assets/skins/wood.png.
"""

from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 256
OUT = Path(__file__).resolve().parents[2] / "assets" / "skins"
rng = np.random.default_rng(1792)


def periodic_noise(cells: int) -> np.ndarray:
    """Smooth value noise in [0, 1] that tiles on a SIZE x SIZE square."""
    grid = rng.random((cells, cells))
    coords = np.arange(SIZE) * cells / SIZE
    i0 = np.floor(coords).astype(int)
    i1 = (i0 + 1) % cells
    t = coords - i0
    t = t * t * (3 - 2 * t)
    rows0 = grid[i0][:, i0] * (1 - t)[None, :] + grid[i0][:, i1] * t[None, :]
    rows1 = grid[i1][:, i0] * (1 - t)[None, :] + grid[i1][:, i1] * t[None, :]
    return rows0 * (1 - t)[:, None] + rows1 * t[:, None]


def fractal(octaves: list[tuple[int, float]]) -> np.ndarray:
    total = sum(w for _, w in octaves)
    out = sum(periodic_noise(c) * w for c, w in octaves) / total
    return (out - out.min()) / (out.max() - out.min())


def to_image(base: tuple[int, int, int], dark: tuple[int, int, int],
             amount: np.ndarray) -> Image.Image:
    b = np.array(base, dtype=float)
    d = np.array(dark, dtype=float)
    rgb = b[None, None, :] * (1 - amount[..., None]) + d[None, None, :] * amount[..., None]
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")


def parchment() -> Image.Image:
    # Broad stains, then fibres. Kept faint: text has to sit on it at 4.5:1.
    stains = fractal([(2, 3.0), (4, 2.0), (8, 1.0)])
    grain = fractal([(32, 1.0), (64, 1.0)])
    amount = 0.10 * stains + 0.05 * grain
    return to_image((0xF1, 0xE4, 0xC6), (0xB8, 0x9A, 0x6A), amount)


def wood() -> Image.Image:
    # Vertical grain: a sine across x, bent by low-frequency noise so the
    # lines wander the way a real board does. Integer frequency keeps it
    # periodic.
    x = np.arange(SIZE)[None, :] / SIZE
    warp = fractal([(2, 2.0), (4, 1.0)]) - 0.5
    rings = 0.5 + 0.5 * np.sin(2 * np.pi * (13 * x + 0.7 * warp))
    fibre = fractal([(4, 1.0), (64, 2.0)])
    amount = 0.45 * rings + 0.55 * fibre
    return to_image((0x5C, 0x3A, 0x24), (0x3A, 0x22, 0x13), amount)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, image in (("parchment", parchment()), ("wood", wood())):
        path = OUT / f"{name}.png"
        image.save(path, optimize=True)
        print(f"{path}  {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
