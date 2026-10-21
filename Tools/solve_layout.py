#!/usr/bin/env python3
"""
solve_layout.py — helper for laying out map regions with layout_sa.c.

Rooms in the given regions move (except those listed in KEEP); every other
placed room stays put as an anchor. Rooms not yet in the layout are dropped
near a neighbour first. The result still wants a human eye: run
make_map.py --preview afterwards and adjust map_layout.txt by hand.

    cc -O2 -o layout_sa layout_sa.c -lm
    python3 solve_layout.py IN.txt OUT.txt REGIONS KEEP ITERS SEED T0 LENW [minx,maxx,miny,maxy]
    e.g. python3 solve_layout.py map_layout.txt out.txt maze-alike NONE 6000000 1 3 1.6 -9,1,3,10
"""
import sys, subprocess, pathlib
HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE))
import make_map as M
from mapdata import CaveData
def run(src, out, regions, keep, iters, seed, T0, lenw, box=(-999,999,-999,999)):
    data = CaveData(M.YAML)
    M.LAYOUT = pathlib.Path(src); pos = M.load_layout()
    keys = [k for k in data.rooms if k in pos or (data.rooms[k]['region'] in regions and k[4:] not in keep)]
    # unplaced movable rooms start near a placed neighbour
    import random; rnd = random.Random(seed)
    occ = set(pos.values())
    for k in keys:
        if k not in pos:
            nb = [c['b'] if c['a']==k else c['a'] for c in data.connections if k in (c['a'],c['b'])]
            base = next((pos[n] for n in nb if n in pos), ((box[0]+box[1])//2 if box[0]>-999 else 0, (box[2]+box[3])//2 if box[2]>-999 else 0))
            for r in range(1,40):
                p = (base[0]+rnd.randint(-r,r), base[1]+rnd.randint(-r,r))
                if not (box[0] <= p[0] <= box[1] and box[2] <= p[1] <= box[3]):
                    continue
                if p not in occ: pos[k]=p; occ.add(p); break
    idx = {k:i for i,k in enumerate(keys)}
    conns = [c for c in data.connections if c['a'] in idx and c['b'] in idx and not c['portal']]
    lines = [f"{len(keys)} {len(conns)} {iters} {seed} {T0} {lenw} {box[0]} {box[1]} {box[2]} {box[3]}"]
    for k in keys:
        movable = data.rooms[k]['region'] in regions and k[4:] not in keep
        lines.append(f"{int(pos[k][0])} {int(pos[k][1])} {0 if movable else 1}")
    from mapdata import VEC
    for c in conns:
        sa = CaveData.side(c['aVerbs'])[0] if c['aVerbs'] else None
        sb = CaveData.side(c['bVerbs'])[0] if c['bVerbs'] else None
        va = VEC[sa] if sa else (0,0); vb = VEC[sb] if sb else (0,0)
        lines.append(f"{idx[c['a']]} {idx[c['b']]} {va[0]} {va[1]} {vb[0]} {vb[1]}")
    r = subprocess.run([str(HERE / 'layout_sa')], input="\n".join(lines), capture_output=True, text=True)
    sys.stderr.write(r.stderr)
    for k, l in zip(keys, r.stdout.split("\n")):
        x, y = l.split(); pos[k] = (int(x), int(y))
    M.LAYOUT = pathlib.Path(out); M.save_layout(pos, data)
if __name__ == '__main__':
    src, out, regions, keep, iters, seed, T0, lenw = sys.argv[1:9]
    box = tuple(int(v) for v in sys.argv[9].split(',')) if len(sys.argv) > 9 else (-999, 999, -999, 999)
    run(src, out, regions.split(','), keep.split(','), int(iters), int(seed), float(T0), float(lenw), box)
