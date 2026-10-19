"""Edits the Phase 5E village splat maps in place, for layout changes after 5E.

The original splat generator was never committed, so instead of regenerating the maps this
applies small, explicit edits that match the 5E look (measured from the committed maps):
  - dirt lanes (splat_a R): 255 inside half-width - 0.3 m, linear edge 0.6 m wide;
  - house contact shade (splat_b A): 153 over the collider footprint, fading out over 1.5 m.

Operations:
  lane(points, width)          paint a dirt lane (max with what is there)
  cobble(points, width)        paint a cobbled road with its dirt shoulder (max with what is there)
  erase_lane(points, width)    fade out a dirt lane segment that no longer leads anywhere,
                               except where a `keep` lane is painted
  move_shade(rect, dx, dz)     remove a house's contact shade and stamp it at the new place

  region(rect, map, channel)   paint a channel over a rectangle with a soft, noisy edge
  disc(centre, radius, ...)    paint a channel over a disc with a soft, noisy edge
  fade(rect, map, channel)     fade a channel out over a rectangle

phase5h() lists the edits for the Phase 5H village spacing pass and phase5h_tools() the pond
footpath; phase7_world() grows the maps for the Whisperwood annex and repaints the forest, and
phase7_roads() widens the main roads;
the matching lane polylines are in assets/textures/terrain/village_layout.json.
Each step was applied once, from the project root:
  python tools/edit_village_splat.py phase5h
  python tools/edit_village_splat.py phase5h-tools
  python tools/edit_village_splat.py phase5h-stall
  python tools/edit_village_splat.py phase7-world
  python tools/edit_village_splat.py phase7-roads
"""
import sys

import numpy as np
from PIL import Image

SPLAT_A = "assets/textures/terrain/village_splat_a.png"
SPLAT_B = "assets/textures/terrain/village_splat_b.png"
# Since Phase 7 the maps cover x -96..96, z -128..64 (192 m at 8 px/m), which takes in the
# Whisperwood annex north of the village; they covered -64..64 (1024 px) before.
ORIGIN_X, ORIGIN_Z, SIZE, RES = -96.0, -128.0, 192.0, 1536
LEGACY_ORIGIN, LEGACY_RES = -64.0, 1024
SHADE, SHADE_RAMP = 153.0, 1.5
LANE_EDGE = 0.6

X, Z = np.meshgrid((np.arange(RES) + 0.5) * SIZE / RES + ORIGIN_X, (np.arange(RES) + 0.5) * SIZE / RES + ORIGIN_Z)
# Smooth noise in [0, 1] for organic edges: a few summed sine waves of world position.
_NOISE = 0.5 + 0.25 * np.sin(X * 0.21 + 1.3) * np.sin(Z * 0.17 + 0.4) + 0.15 * np.sin(X * 0.53 - Z * 0.41 + 2.0) + 0.1 * np.sin(Z * 0.9 + X * 0.07)


def _segment_distance(p, q):
    vx, vz = q[0] - p[0], q[1] - p[1]
    t = np.clip(((X - p[0]) * vx + (Z - p[1]) * vz) / (vx * vx + vz * vz), 0.0, 1.0)
    return np.hypot(X - (p[0] + t * vx), Z - (p[1] + t * vz))


def _polyline_distance(points):
    return np.min([_segment_distance(points[i], points[i + 1]) for i in range(len(points) - 1)], axis=0)


def _lane_value(points, width):
    inner = width * 0.5 - LANE_EDGE * 0.5
    return np.clip((inner + LANE_EDGE - _polyline_distance(points)) / LANE_EDGE, 0.0, 1.0) * 255.0


def _rect_shade(rect):
    x0, z0, x1, z1 = rect
    dx = np.maximum(np.maximum(x0 - X, X - x1), 0.0)
    dz = np.maximum(np.maximum(z0 - Z, Z - z1), 0.0)
    return np.clip(1.0 - np.hypot(dx, dz) / SHADE_RAMP, 0.0, 1.0) * SHADE


def _grow(image):
    """Places a pre-Phase-7 1024 px map (x, z -64..64) on the 192 m canvas; other sizes pass."""
    if image.shape[0] == RES:
        return image
    assert image.shape[0] == LEGACY_RES, image.shape
    canvas = np.zeros((RES, RES, 4))
    ox = int((LEGACY_ORIGIN - ORIGIN_X) * RES / SIZE)
    oz = int((LEGACY_ORIGIN - ORIGIN_Z) * RES / SIZE)
    canvas[oz:oz + LEGACY_RES, ox:ox + LEGACY_RES] = image
    return canvas


def _rect_weight(rect, edge, noise):
    """1 inside rect, fading to 0 over `edge` metres outside it, the edge warped by noise."""
    x0, z0, x1, z1 = rect
    dx = np.maximum(np.maximum(x0 - X, X - x1), 0.0)
    dz = np.maximum(np.maximum(z0 - Z, Z - z1), 0.0)
    d = np.hypot(dx, dz) - (_NOISE - 0.5) * 2.0 * noise
    return np.clip(1.0 - d / edge, 0.0, 1.0)


class Splats:
    def __init__(self):
        self.a = _grow(np.array(Image.open(SPLAT_A).convert("RGBA")).astype(np.float64))
        self.b = _grow(np.array(Image.open(SPLAT_B).convert("RGBA")).astype(np.float64))

    def _channel(self, splat_map, channel):
        return (self.a if splat_map == "a" else self.b)[..., channel]

    def region(self, rect, splat_map, channel, edge=3.0, noise=2.5, strength=255.0):
        values = self._channel(splat_map, channel)
        values[:] = np.maximum(values, _rect_weight(rect, edge, noise) * strength)

    def disc(self, centre, radius, splat_map, channel, edge=1.5, noise=0.8, strength=255.0):
        d = np.hypot(X - centre[0], Z - centre[1]) - radius - (_NOISE - 0.5) * 2.0 * noise
        values = self._channel(splat_map, channel)
        values[:] = np.maximum(values, np.clip(1.0 - d / edge, 0.0, 1.0) * strength)

    def fade(self, rect, splat_map, channel, edge=3.0):
        values = self._channel(splat_map, channel)
        values[:] = values * (1.0 - _rect_weight(rect, edge, 0.0))

    def lane(self, points, width=2.4):
        self.a[..., 0] = np.maximum(self.a[..., 0], _lane_value(points, width))

    def cobble(self, points, width=3.2):
        # Measured from the 5E roads: stones full to width/2 - 0.3 m with a 0.6 m edge, on a
        # dirt shoulder 1 m wider each side that fades over 0.9 m.
        self.a[..., 1] = np.maximum(self.a[..., 1], _lane_value(points, width))
        shoulder = np.clip((width * 0.5 + 1.0 - _polyline_distance(points)) / 0.9, 0.0, 1.0) * 255.0
        self.a[..., 0] = np.maximum(self.a[..., 0], shoulder)

    def erase_lane(self, points, width=2.4, keep=()):
        fade = _lane_value(points, width + LANE_EDGE)
        kept = np.zeros_like(fade)
        for k in keep:
            kept = np.maximum(kept, _lane_value(k[0], k[1]))
        self.a[..., 0] = np.maximum(np.minimum(self.a[..., 0], 255.0 - fade), kept)

    def move_shade(self, rect, dx, dz):
        alpha = self.b[..., 3]
        alpha = np.maximum(alpha - _rect_shade(rect), 0.0)
        moved = (rect[0] + dx, rect[1] + dz, rect[2] + dx, rect[3] + dz)
        self.b[..., 3] = np.maximum(alpha, _rect_shade(moved))

    def save(self):
        Image.fromarray(np.rint(self.a).astype(np.uint8), "RGBA").save(SPLAT_A)
        Image.fromarray(np.rint(self.b).astype(np.uint8), "RGBA").save(SPLAT_B)


# Phase 5H: more space between houses (see docs/PHASE5H_VILLAGE_AND_TOOLS.md).
# Collider footprints (x0, z0, x1, z1) before the move, and the move.
BLUE_LANE = [(-4.0, -6.6), (-5.3, -10.4), (-5.8, -13.8), (-8.6, -17.2)]
OAK_SPUR = [(-19.6, 4.7), (-19.6, 7.8)]
FERN_LANE = [(17.0, 1.4), (17.6, 6.0), (18.6, 9.6), (19.8, 11.2)]


def phase5h(s):
    s.move_shade((-5.6, -19.5, -2.4, -14.5), -4.6, -3.2)   # CottageBlue
    s.move_shade((-18.6, 7.5, -15.4, 12.5), -2.6, 0.6)     # CottageOak
    s.move_shade((16.1, 10.6, 19.9, 15.4), 1.8, 1.2)       # CottageFern
    # The old end of the blue lane ran to the old door; the new lane bends west to the new one.
    s.erase_lane([(-5.6, -10.4), (-4.6, -14.0)], keep=[(BLUE_LANE, 2.4)])
    s.lane(BLUE_LANE)
    s.lane(OAK_SPUR)
    s.lane(FERN_LANE)


# Phase 5H tools: the footpath from the west farm track to the Willowmere Pond jetty.
POND_PATH = [(-29.0, -15.0), (-26.0, -16.6), (-23.5, -18.0)]


def phase5h_tools(s):
    s.lane(POND_PATH)


# Phase 5H tools: the smithy's spur continued south across the west lane to the tool stall.
STALL_SPUR = [(-26.1, 3.0), (-26.2, 7.4)]


def phase5h_stall(s):
    s.lane(STALL_SPUR)


# Phase 7: Whisperwood moves 70 m north into the annex (x -20..44, z -124..-44). The old forest
# quarter of the village becomes open outskirts crossed by the trail.
OLD_FOREST = (-4.0, -46.0, 32.0, -16.0)
NEW_FOREST = (-18.0, -122.0, 42.0, -53.0)
CLEARING = ((14.0, -104.0), 5.8)
GLADES = [((-2.0, -80.0), 4.5), ((35.0, -90.0), 4.0)]
WHISPERWOOD_TRAIL = [(14.0, -28.6), (12.6, -36.0), (15.5, -45.0), (14.2, -53.0), (18.5, -62.0),
                     (13.5, -71.0), (16.5, -80.0), (14.0, -90.0), (14.0, -98.6)]
GLADE_PATH = [(13.5, -71.0), (6.0, -76.0), (-2.0, -80.0)]
HOLLOW_PATH = [(16.5, -80.0), (25.0, -84.0), (31.0, -86.0), (35.0, -90.0)]


def phase7_world(s):
    s.fade(OLD_FOREST, "b", 0)   # forest floor
    s.fade(OLD_FOREST, "b", 1)   # clearing moss
    s.region(NEW_FOREST, "b", 0, edge=4.0, noise=3.0)
    s.disc(CLEARING[0], CLEARING[1], "b", 1)
    for centre, radius in GLADES:
        s.disc(centre, radius, "b", 1, strength=200.0)
    s.lane(WHISPERWOOD_TRAIL, 2.8)
    s.lane(GLADE_PATH, 2.0)
    s.lane(HOLLOW_PATH, 2.0)


# Phase 7 village pass: the three cobbled roads out of the plaza are widened (3.2 -> 4.4 m,
# the south road 2.6 -> 3.4 m) and the forest lane and Whisperwood trail by 0.6 m.
MARKET_ROAD = [(7.0, 0.8), (12.0, 1.0), (19.5, 1.0), (23.6, -0.8)]
FOREST_ROAD = [(4.8, -5.2), (7.6, -9.6), (11.4, -15.6), (13.6, -18.6)]
SOUTH_ROAD = [(5.0, 5.0), (9.8, 8.2), (10.2, 13.8), (9.8, 17.0), (4.2, 17.2)]
FOREST_LANE = [(13.6, -18.6), (14.0, -20.2), (14.0, -24.0), (14.0, -28.6)]


def phase7_roads(s):
    s.cobble(MARKET_ROAD, 4.4)
    s.cobble(FOREST_ROAD, 4.4)
    s.cobble(SOUTH_ROAD, 3.4)
    s.lane(FOREST_LANE, 3.2)
    s.lane(WHISPERWOOD_TRAIL, 3.4)


# Each step is applied once, in order; re-running one repeats its edits.
STEPS = {"phase5h": phase5h, "phase5h-tools": phase5h_tools, "phase5h-stall": phase5h_stall,
         "phase7-world": phase7_world, "phase7-roads": phase7_roads}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in STEPS:
        sys.exit(__doc__)
    splats = Splats()
    STEPS[sys.argv[1]](splats)
    splats.save()
    print("edited", SPLAT_A, SPLAT_B)
