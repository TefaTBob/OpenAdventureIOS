#!/usr/bin/env python3
"""
make_map.py — builds the in-app cave map (Trizbort style) from adventure.yaml.

    python3 make_map.py [--preview map.png]   # check layout, write JSON (+ picture)

Room positions live in map_layout.txt (one "KEY col row" per line). They were
found with solve_layout.py (a simulated-annealing helper) and then tuned by
hand. Connections, exits and labels come from the game data via mapdata.py.

Checks printed on every run: overlapping rooms, compass exits drawn pointing
the wrong way, lines passing through other rooms, and line crossings.
"""
import json
import math
import sys
from pathlib import Path

from mapdata import VEC, CaveData, VERB_WORDS

HERE = Path(__file__).parent
YAML = HERE / "adventure.yaml"
LAYOUT = HERE / "map_layout.txt"
OUT_JSON = HERE.parent / "OpenAdventure" / "Resources" / "cave_map.json"

# Geometry in grid units: a room box inside each cell.
BOX_W, BOX_H = 0.74, 0.52
PORT_ORDER = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]


def load_layout():
    pos = {}
    if LAYOUT.exists():
        for line in LAYOUT.read_text().splitlines():
            line = line.split("#")[0].strip()
            if not line:
                continue
            key, x, y = line.split()
            pos["LOC_" + key] = (float(x), float(y))
    return pos


def save_layout(pos, data):
    order = sorted(pos, key=lambda k: (data.rooms[k]["region"], pos[k][1], pos[k][0]))
    lines = ["# Map grid positions: KEY col row (row grows southward). Hand-tuned.", ""]
    region = None
    for k in order:
        r = data.rooms[k]["region"]
        if r != region:
            lines.append(f"\n# {r}")
            region = r
        x, y = pos[k]
        lines.append(f"{k[4:]:<16} {x:g} {y:g}")
    LAYOUT.write_text("\n".join(lines) + "\n")


# ------------------------------------------------------------------ ports

def snap_dir(dx, dy):
    """Nearest of the eight compass ports for a vector (y grows south)."""
    ang = math.degrees(math.atan2(-dy, dx)) % 360  # 0 = east, 90 = north
    names = ["e", "ne", "n", "nw", "w", "sw", "s", "se"]
    return names[int(((ang + 22.5) % 360) // 45)]


def port_offset(port):
    vx, vy = VEC[port]
    return vx * BOX_W / 2, vy * BOX_H / 2


DIR_WORDS = {"n": "north", "s": "south", "e": "east", "w": "west",
             "ne": "northeast", "nw": "northwest", "se": "southeast", "sw": "southwest"}
ANGLE = {"e": 0, "ne": 45, "n": 90, "nw": 135, "w": 180, "sw": 225, "s": 270, "se": 315}


def resolve_ports(data, pos):
    """Pick the box side each connection end leaves from.

    Ends with a compass exit use that side. Ends without one (up/down/in/out,
    or the arrival end of a one-way passage) use the free side that best
    faces the other room, so they don't pile onto a compass exit's side.
    """
    used = {}
    pending = []
    conns = []
    for c in data.connections:
        a, b = c["a"], c["b"]
        out = {"a": data.rooms[a]["id"], "b": data.rooms[b]["id"]}
        for end, verbs in (("a", c["aVerbs"]), ("b", c["bVerbs"])):
            compass, word = CaveData.side(verbs) if verbs else (None, None)
            out[end + "Label"] = word or ""
            if compass and a != b:
                # A compass exit that leads the opposite way on the map
                # (the cave isn't flat): leave from the side facing the
                # room, and say which way you actually go.
                me, other = pos[c[end]], pos[c["b" if end == "a" else "a"]]
                vx, vy = VEC[compass]
                if vx * (other[0] - me[0]) + vy * (other[1] - me[1]) <= 0:
                    out[end + "Label"] = DIR_WORDS[compass] + (" " + word if word else "")
                    compass = None
            if compass:
                out[end + "Port"] = compass
                used.setdefault(c[end], set()).add(compass)
            elif a == b:
                out[end + "Port"] = "n"
            else:
                pending.append((out, end, c[end], c["b" if end == "a" else "a"]))
        out["aToB"] = c["aVerbs"] is not None
        out["bToA"] = c["bVerbs"] is not None
        out["portal"] = c["portal"]
        conns.append(out)
    for out, end, me, other in pending:
        dx, dy = pos[other][0] - pos[me][0], pos[other][1] - pos[me][1]
        want = math.degrees(math.atan2(-dy, dx)) % 360
        taken = used.setdefault(me, set())

        def score(p):
            diff = abs((ANGLE[p] - want + 180) % 360 - 180)
            return diff + (60 if p in taken else 0)
        port = min(ANGLE, key=score)
        out[end + "Port"] = port
        taken.add(port)
    return conns


def endpoints(conn, pos_by_id):
    ax, ay = pos_by_id[conn["a"]]
    bx, by = pos_by_id[conn["b"]]
    oa, ob = port_offset(conn["aPort"]), port_offset(conn["bPort"])
    return (ax + oa[0], ay + oa[1]), (bx + ob[0], by + ob[1])


def route(conn, pos_by_id, stub=0.16):
    """Polyline: port, short stub straight out, then across, then stub in."""
    p, q = endpoints(conn, pos_by_id)
    va, vb = VEC[conn["aPort"]], VEC[conn["bPort"]]
    na, nb = math.hypot(*va), math.hypot(*vb)
    p2 = (p[0] + va[0] / na * stub, p[1] + va[1] / na * stub)
    q2 = (q[0] + vb[0] / nb * stub, q[1] + vb[1] / nb * stub)
    return [p, p2, q2, q]


# ------------------------------------------------------------------ checks

def seg_intersect(p1, p2, p3, p4):
    def orient(a, b, c):
        v = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        return 0 if abs(v) < 1e-9 else (1 if v > 0 else -1)
    o1, o2 = orient(p1, p2, p3), orient(p1, p2, p4)
    o3, o4 = orient(p3, p4, p1), orient(p3, p4, p2)
    return o1 * o2 < 0 and o3 * o4 < 0


def seg_hits_box(p, q, cx, cy, pad=0.0):
    """Does segment pq pass through the box centred at (cx, cy)?"""
    hw, hh = BOX_W / 2 + pad, BOX_H / 2 + pad
    steps = max(2, int(math.hypot(q[0] - p[0], q[1] - p[1]) / 0.05))
    for i in range(1, steps):
        t = i / steps
        x, y = p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t
        if abs(x - cx) < hw and abs(y - cy) < hh:
            return True
    return False


def check(data, pos, conns, verbose=True):
    pos_by_id = {data.rooms[k]["id"]: v for k, v in pos.items()}
    problems = []
    # overlaps
    seen = {}
    for k, p in pos.items():
        if p in seen:
            problems.append(f"overlap: {k} and {seen[p]} at {p}")
        seen[p] = k
    # direction fidelity: does each compass exit point the way it says?
    good = total = 0
    wrong = []
    for c in conns:
        if c["a"] == c["b"] or c["portal"]:
            continue
        for end, other in (("a", "b"), ("b", "a")):
            port = c[end + "Port"]
            label = c[end + "Label"]
            me, them = pos_by_id[c[end]], pos_by_id[c[other]]
            want = VEC[port]
            dx, dy = them[0] - me[0], them[1] - me[1]
            sx = (dx > 0) - (dx < 0)
            sy = (dy > 0) - (dy < 0)
            total += 1
            if (sx, sy) == want:
                good += 1
            elif want[0] * dx + want[1] * dy <= 0 and label == "":
                wrong.append(f"{data.names[c[end]][4:]} --{port}--> {data.names[c[other]][4:]}")
    # lines through boxes
    hits = []
    for c in conns:
        if c["a"] == c["b"] or c["portal"]:
            continue
        pts = route(c, pos_by_id)
        for k, (x, y) in pos.items():
            rid = data.rooms[k]["id"]
            if rid in (c["a"], c["b"]):
                continue
            if any(seg_hits_box(pts[i], pts[i + 1], x, y, pad=0.02) for i in range(3)):
                hits.append(f"{data.names[c['a']][4:]}-{data.names[c['b']][4:]} crosses {k[4:]}")
    # crossings
    segs = []
    for c in conns:
        if c["a"] != c["b"] and not c["portal"]:
            pts = route(c, pos_by_id)
            segs.append((c, pts))
    crossings = 0
    for i in range(len(segs)):
        for j in range(i + 1, len(segs)):
            a, b = segs[i][1], segs[j][1]
            if any(seg_intersect(a[s], a[s + 1], b[t], b[t + 1]) for s in range(3) for t in range(3)):
                crossings += 1
    if verbose:
        print(f"rooms {len(pos)}, connections {len(conns)}")
        print(f"compass exits pointing the right way: {good}/{total}")
        print(f"exits pointing backwards: {len(wrong)}")
        for w in wrong:
            print("   ", w)
        print(f"lines through other rooms: {len(hits)}")
        for h in hits:
            print("   ", h)
        print(f"line crossings: {crossings}")
        for p in problems:
            print("   ", p)
    return problems, wrong, hits, crossings


# ------------------------------------------------------------------ solver

# ------------------------------------------------------------------ output

REGION_NOTES = {
    "maze-alike": "Maze of twisty little passages, all alike",
    "maze-different": "Maze of twisty passages, all different — tap a room for its exits",
    "forest": "Forest — the paths all look alike; tap a clearing for its exits",
    "repository": "Repository (endgame)",
}


def build_json(data, pos, conns):
    rooms = []
    for k, r in data.rooms.items():
        x, y = pos[k]
        rooms.append({"id": r["id"], "locs": r["locs"], "label": r["label"],
                      "region": r["region"], "x": x, "y": y})
    # exits list per room, for the tap-to-inspect panel
    exits = {}
    for src, dst, verbs, cond in data.exits:
        sid, did = data.rooms[src]["id"], data.rooms[dst]["id"]
        words = [VERB_WORDS.get(v, v.lower()) for v in verbs]
        exits.setdefault(sid, []).append({"to": did, "words": words, "conditional": cond})
    for r in rooms:
        r["exits"] = exits.get(r["id"], [])
    regions = []
    for reg, note in REGION_NOTES.items():
        pts = [pos[k] for k, r in data.rooms.items() if r["region"] == reg]
        if pts:
            regions.append({"region": reg, "title": note,
                            "x0": min(p[0] for p in pts) - 0.5, "y0": min(p[1] for p in pts) - 0.5,
                            "x1": max(p[0] for p in pts) + 0.5, "y1": max(p[1] for p in pts) + 0.5})
    xs = [p[0] for p in pos.values()]
    ys = [p[1] for p in pos.values()]
    return {
        "source": "Generated from Open Adventure 1.22 adventure.yaml by Tools/make_map.py",
        "box": {"w": BOX_W, "h": BOX_H},
        "bounds": {"x0": min(xs) - 1, "y0": min(ys) - 1, "x1": max(xs) + 1, "y1": max(ys) + 1},
        "rooms": rooms, "connections": conns, "regions": regions,
    }


def render_preview(doc, path, scale=130):
    from PIL import Image, ImageDraw, ImageFont
    b = doc["bounds"]
    W = int((b["x1"] - b["x0"]) * scale)
    H = int((b["y1"] - b["y0"]) * scale)
    im = Image.new("RGB", (W, H), (250, 248, 240))
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", int(scale * 0.1))
        small = ImageFont.truetype("DejaVuSans.ttf", int(scale * 0.075))
        big = ImageFont.truetype("DejaVuSans-Bold.ttf", int(scale * 0.12))
    except OSError:
        font = small = big = ImageFont.load_default()

    def P(x, y):
        return ((x - b["x0"]) * scale, (y - b["y0"]) * scale)

    ink = (40, 40, 60)
    for r in doc["regions"]:
        d.rectangle([P(r["x0"], r["y0"]), P(r["x1"], r["y1"])], outline=(170, 170, 200), width=2)
        d.text(P(r["x0"] + 0.05, r["y0"] + 0.03), r["title"], fill=(120, 120, 160), font=big)
    by_id = {r["id"]: (r["x"], r["y"]) for r in doc["rooms"]}
    diff_ids = {r["id"] for r in doc["rooms"] if r["region"] == "maze-different"}
    for c in doc["connections"]:
        if c["a"] in diff_ids and c["b"] in diff_ids:
            continue
        if c["a"] == c["b"]:
            x, y = by_id[c["a"]]
            ox, oy = port_offset(c["aPort"])
            cx, cy = P(x + ox * 1.25, y + oy * 1.25)
            rr = scale * 0.08
            d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=ink, width=2)
            continue
        if c["portal"]:
            names = {r["id"]: r["label"] for r in doc["rooms"]}
            for end, other in (("a", "b"), ("b", "a")):
                x, y = by_id[c[end]]
                ox, oy = port_offset(c[end + "Port"])
                vx, vy = VEC[c[end + "Port"]]
                n = math.hypot(vx, vy)
                p0 = P(x + ox, y + oy)
                p1 = P(x + ox + vx / n * 0.28, y + oy + vy / n * 0.28)
                d.line([p0, p1], fill=ink, width=2)
                d.text(P(x + ox + vx / n * 0.36, y + oy + vy / n * 0.36), "to " + names[c[other]],
                       fill=(40, 90, 150), font=small, anchor="mm")
            continue
        pts = [P(*p) for p in route(c, by_id)]
        d.line(pts, fill=ink, width=2)
        if c["aToB"] != c["bToA"]:
            # arrow at the middle toward the destination
            (x1, y1), (x2, y2) = pts[1], pts[2]
            if not c["aToB"]:
                x1, y1, x2, y2 = x2, y2, x1, y1
            mx, my = (x1 + x2) / 2, (y1 + y2) / 2
            ang = math.atan2(y2 - y1, x2 - x1)
            s = scale * 0.07
            d.polygon([(mx + math.cos(ang) * s, my + math.sin(ang) * s),
                       (mx + math.cos(ang + 2.5) * s, my + math.sin(ang + 2.5) * s),
                       (mx + math.cos(ang - 2.5) * s, my + math.sin(ang - 2.5) * s)], fill=ink)
        for end in ("a", "b"):
            lab = c[end + "Label"]
            if lab:
                x, y = by_id[c[end]]
                ox, oy = port_offset(c[end + "Port"])
                vx, vy = VEC[c[end + "Port"]]
                tx, ty = P(x + ox + vx * 0.1 + (0.06 if vx == 0 else 0), y + oy + vy * 0.1 + (0.05 if vy == 0 else 0))
                d.text((tx, ty), lab, fill=(150, 40, 40), font=small, anchor="mm")
    for r in doc["rooms"]:
        x, y = r["x"], r["y"]
        x0, y0 = P(x - BOX_W / 2, y - BOX_H / 2)
        x1, y1 = P(x + BOX_W / 2, y + BOX_H / 2)
        d.rectangle([x0, y0, x1, y1], fill=(255, 255, 255), outline=ink, width=2)
        words = r["label"].split()
        lines, cur = [], ""
        for w in words:
            if len(cur) + len(w) + 1 > 13 and cur:
                lines.append(cur)
                cur = w
            else:
                cur = (cur + " " + w).strip()
        lines.append(cur)
        cy = (y0 + y1) / 2 - (len(lines) - 1) * scale * 0.06
        for i, ln in enumerate(lines[:3]):
            d.text(((x0 + x1) / 2, cy + i * scale * 0.12), ln, fill=ink, font=font, anchor="mm")
    im.save(path)


def main():
    data = CaveData(YAML)
    pos = load_layout()
    missing = [k for k in data.rooms if k not in pos]
    if missing:
        print("unplaced:", " ".join(m[4:] for m in missing))
        if "--partial" not in sys.argv:
            sys.exit(1)
        data.rooms = {k: v for k, v in data.rooms.items() if k in pos}
        data.connections = [c for c in data.connections if c["a"] in pos and c["b"] in pos]
        data.exits = [e for e in data.exits if e[0] in pos and e[1] in pos]
    unknown = [k for k in pos if k not in data.rooms]
    if unknown:
        print("unknown rooms in layout:", unknown)
        sys.exit(1)
    pos_by_id = {data.rooms[k]["id"]: v for k, v in pos.items()}
    conns = resolve_ports(data, pos)
    problems, wrong, hits, crossings = check(data, pos, conns)
    doc = build_json(data, pos, conns)
    if not missing:
        OUT_JSON.write_text(json.dumps(doc, indent=1))
    preview = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    if preview:
        render_preview(doc, preview)
    if problems:
        sys.exit(1)


if __name__ == "__main__":
    main()
