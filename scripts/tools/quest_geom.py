"""Shared 2D geometry for the field-quest tools (#294).

Sibling import (`from quest_geom import …`) — both consumers run as
scripts from scripts/tools, so the directory is already on sys.path.
"""


def point_in_triangle(px: float, pz: float, tri: tuple) -> bool:
    """Test if point (px, pz) is inside triangle tri = ((x1,z1), (x2,z2), (x3,z3))."""
    (x1, z1), (x2, z2), (x3, z3) = tri
    d1 = (px - x2) * (z1 - z2) - (x1 - x2) * (pz - z2)
    d2 = (px - x3) * (z2 - z3) - (x2 - x3) * (pz - z3)
    d3 = (px - x1) * (z3 - z1) - (x3 - x1) * (pz - z1)
    has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (has_neg and has_pos)
