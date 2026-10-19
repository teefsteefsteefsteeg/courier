"""Edits the Phase 5E village splat maps in place, for layout changes after 5E.

The original splat generator was never committed, so instead of regenerating the maps this
applies small, explicit edits that match the 5E look (measured from the committed maps):
  - dirt lanes (splat_a R): 255 inside half-width - 0.3 m, linear edge 0.6 m wide;
  - house contact shade (splat_b A): 153 over the collider footprint, fading out over 1.5 m.

Operations:
  lane(points, width)          paint a dirt lane (max with what is there)
  erase_lane(points, width)    fade out a dirt lane segment that no longer leads anywhere,
                               except where a `keep` lane is painted
  move_shade(rect, dx, dz)     remove a house's contact shade and stamp it at the new place

phase5h() lists the edits for the Phase 5H village spacing pass and phase5h_tools() the pond
footpath; the matching lane polylines are in assets/textures/terrain/village_layout.json.
Each step was applied once, from the project root:
  python tools/edit_village_splat.py phase5h
  python tools/edit_village_splat.py phase5h-tools
  python tools/edit_village_splat.py phase5h-stall
"""
import sys

import numpy as np
from PIL import Image

SPLAT_A = "assets/textures/terrain/village_splat_a.png"
SPLAT_B = "assets/textures/terrain/village_splat_b.png"
ORIGIN, SIZE, RES = -64.0, 128.0, 1024
SHADE, SHADE_RAMP = 153.0, 1.5
LANE_EDGE = 0.6

_px = (np.arange(RES) + 0.5) * SIZE / RES + ORIGIN
X, Z = np.meshgrid(_px, _px)


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


class Splats:
    def __init__(self):
        self.a = np.array(Image.open(SPLAT_A).convert("RGBA")).astype(np.float64)
        self.b = np.array(Image.open(SPLAT_B).convert("RGBA")).astype(np.float64)

    def lane(self, points, width=2.4):
        self.a[..., 0] = np.maximum(self.a[..., 0], _lane_value(points, width))

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


# Each step is applied once, in order; re-running one repeats its edits.
STEPS = {"phase5h": phase5h, "phase5h-tools": phase5h_tools, "phase5h-stall": phase5h_stall}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in STEPS:
        sys.exit(__doc__)
    splats = Splats()
    STEPS[sys.argv[1]](splats)
    splats.save()
    print("edited", SPLAT_A, SPLAT_B)
