"""
mapdata.py — turns Open Adventure's adventure.yaml into map rooms, exits and
Trizbort-style connections. Shared by make_map.py (layout + JSON) and the
checks. Nothing here is hand-entered except room names and which engine
locations share a box; every connection comes from the game's travel table.
"""
import yaml

COMPASS = {
    "NORTH": "n", "SOUTH": "s", "EAST": "e", "WEST": "w",
    "NE": "ne", "NW": "nw", "SE": "se", "SW": "sw",
}
VEC = {"n": (0, -1), "s": (0, 1), "e": (1, 0), "w": (-1, 0),
       "ne": (1, -1), "nw": (-1, -1), "se": (1, 1), "sw": (-1, 1)}
OPPOSITE = {"n": "s", "s": "n", "e": "w", "w": "e",
            "ne": "sw", "sw": "ne", "nw": "se", "se": "nw"}
VERTICAL = {"UPWAR": "up", "DOWN": "down"}
INOUT = {"INWAR": "in", "ENTER": "in", "OUT": "out", "OUTDO": "out"}
# Words that describe a way of moving rather than naming a destination.
MOVES = {"CLIMB": "climb", "CRAWL": "crawl", "OVER": "over", "ACROS": "across",
         "CROSS": "cross", "JUMP": "jump", "UPSTR": "upstream", "DOWNS": "downstream",
         "FLY": "fly"}
MAGIC = {"XYZZY", "PLUGH", "PLOVE"}
HIDE_INSIDE = {"forest", "maze-different"}
# Passages drawn as labelled stubs at both ends instead of a line across
# the map ("to Twisty Maze 1"), like an off-page connector.
PORTALS = {
    frozenset({"LOC_LONGWEST", "LOC_DIFFERENT1"}),
    frozenset({"LOC_TOPSTALACTITE", "LOC_ALIKE4"}),
    frozenset({"LOC_TOPSTALACTITE", "LOC_ALIKE6"}),
    frozenset({"LOC_TOPSTALACTITE", "LOC_ALIKE9"}),
    frozenset({"LOC_PITBRINK", "LOC_BIRDCHAMBER"}),
}

# Readable words for every travel verb (for the room-exits inspector).
VERB_WORDS = {
    "NORTH": "north", "SOUTH": "south", "EAST": "east", "WEST": "west",
    "NE": "northeast", "NW": "northwest", "SE": "southeast", "SW": "southwest",
    "UPWAR": "up", "DOWN": "down", "INWAR": "in", "ENTER": "enter", "OUT": "out",
    "OUTDO": "outdoors", "CLIMB": "climb", "CRAWL": "crawl", "OVER": "over",
    "ACROS": "across", "CROSS": "cross", "JUMP": "jump", "UPSTR": "upstream",
    "DOWNS": "downstream", "ROAD": "road", "BUILD": "building", "FORES": "forest",
    "GULLY": "gully", "STREA": "stream", "DEPRE": "depression", "VALLE": "valley",
    "COBBL": "cobble", "DEBRI": "debris", "CANYO": "canyon", "PASSA": "passage",
    "LOW": "low", "DARK": "dark", "ENTRA": "entrance", "PIT": "pit", "STEPS": "steps",
    "DOME": "dome", "HALL": "hall", "STAIR": "stairs", "FORWA": "forward",
    "LEFT": "left", "RIGHT": "right", "Y2": "y2", "CRACK": "crack", "WALL": "wall",
    "BROKE": "broken", "HOLE": "hole", "FLOOR": "floor", "BEDQU": "bedquilt",
    "SLAB": "slab", "SECRE": "secret", "ROOM": "room", "SHELL": "shell",
    "ORIEN": "oriental", "CAVER": "cavern", "GIANT": "giant", "RESER": "reservoir",
    "VIEW": "view", "FORK": "fork", "BARRE": "barren", "SURFA": "surface",
    "BED": "bed", "FLY": "fly (on the rug)",
}

# Several engine locations that are one place on a map.
MERGE = {
    # The dragon's canyon: one location before the dragon dies, another after.
    "LOC_SECRET5": "LOC_SECRET4",
    "LOC_SECRET6": "LOC_SECRET4",
}

# Engine locations with no box. (Forwarders — one-way messages and deaths —
# are detected automatically.)
SKIP = {"LOC_NOWHERE"}

LABELS = {
    "START": "Outside Building", "HILL": "Hill in Road", "BUILDING": "Well House",
    "VALLEY": "Valley", "ROADEND": "End of Road", "CLIFF": "Cliff",
    "SLIT": "Slit in Streambed", "GRATE": "Outside Grate",
    "BELOWGRATE": "Below the Grate", "COBBLE": "Cobble Crawl", "DEBRIS": "Debris Room",
    "AWKWARD": "Awkward Canyon", "BIRDCHAMBER": "Bird Chamber",
    "PITTOP": "Top of Small Pit", "MISTHALL": "Hall of Mists",
    "EASTBANK": "East Bank of Fissure", "NUGGET": "Nugget of Gold Room",
    "KINGHALL": "Hall of the Mountain King", "WESTEND": "West End of Twopit Room",
    "EASTPIT": "East Pit", "WESTPIT": "West Pit", "WESTBANK": "West Bank of Fissure",
    "FLOORHOLE": "Low N/S Passage", "SOUTHSIDE": "South Side Chamber",
    "WESTSIDE": "West Side Chamber", "Y2": "Y2", "JUMBLE": "Rock Jumble",
    "WINDOW1": "Window on Pit", "BROKEN": "Dirty Passage",
    "SMALLPITBRINK": "Brink of Small Pit", "SMALLPIT": "Small Pit Bottom",
    "DUSTY": "Dusty Rock Room", "MISTWEST": "West End of Hall of Mists",
    "PITBRINK": "Brink of Pit", "LONGEAST": "East End of Long Hall",
    "LONGWEST": "West End of Long Hall", "CROSSOVER": "Crossover",
    "DEADEND7": "Dead End", "COMPLEX": "Complex Junction", "BEDQUILT": "Bedquilt",
    "SWISSCHEESE": "Swiss Cheese Room", "EASTEND": "East End of Twopit Room",
    "SLAB": "Slab Room", "SECRET1": "Secret N/S Canyon", "SECRET2": "Secret Canyon",
    "THREEJUNCTION": "Junction of Three Canyons", "LOWROOM": "Large Low Room",
    "DEADCRAWL": "Dead-End Crawl", "SECRET3": "Secret E/W Canyon",
    "WIDEPLACE": "Wide Place", "TIGHTPLACE": "Tight Canyon", "TALL": "Tall E/W Canyon",
    "BOULDERS1": "Boulders", "NARROW": "Narrow Corridor",
    "INCLINE": "Steep Incline", "GIANTROOM": "Giant Room", "CAVEIN": "Cave-In",
    "IMMENSE": "Immense N/S Passage", "WATERFALL": "Cavern with Waterfall",
    "SOFTROOM": "Soft Room", "ORIENTAL": "Oriental Room", "MISTY": "Misty Cavern",
    "ALCOVE": "Alcove", "PLOVER": "Plover Room", "DARKROOM": "Dark Room",
    "ARCHED": "Arched Hall", "SHELLROOM": "Shell Room", "SLOPING1": "Sloping Corridor",
    "CULDESAC": "Cul-de-Sac", "ANTEROOM": "Anteroom", "WITTSEND": "Witt's End",
    "MIRRORCANYON": "Mirror Canyon", "WINDOW2": "Window on Pit",
    "TOPSTALACTITE": "Top of Stalactite", "RESERVOIR": "Reservoir",
    "NE": "Repository NE End", "SW": "Repository SW End",
    "SWCHASM": "SW Side of Chasm", "WINDING": "Winding Corridor",
    "SECRET4": "Secret Canyon", "NECHASM": "NE Side of Chasm",
    "CORRIDOR": "Long E/W Corridor", "FORK": "Fork in Path",
    "WARMWALLS": "Warm Junction", "BREATHTAKING": "Breath-Taking View",
    "BOULDERS2": "Chamber of Boulders", "LIMESTONE": "Limestone Passage",
    "BARRENFRONT": "Front of Barren Room", "BARRENROOM": "Barren Room",
    "DEADEND13": "Dead End", "ROUGHHEWN": "Rough-Hewn Corridor",
    "LARGE": "Large Chamber", "STOREROOM": "Ogre's Storeroom",
    "RESBOTTOM": "Bottom of Reservoir", "RESNORTH": "North of Reservoir",
    "TREACHEROUS": "Rocky Passage", "STEEP": "Steep Incline",
    "CLIFFBASE": "Base of Cliff", "CLIFFACE": "Vertical Cliff",
    "CLIFFLEDGE": "Clifftop", "REACHDEAD": "Dead End", "LEDGE": "Ledge",
}


def region_for(key, cond):
    if key == "LOC_TOPSTALACTITE":
        return "cave"  # flagged as maze by the engine, but it's above the maze
    if cond.get("FOREST"):
        return "forest"
    if cond.get("ABOVE"):
        return "surface"
    if cond.get("ALLDIFFERENT") and key != "LOC_DEADEND13":
        return "maze-different"
    if cond.get("ALLALIKE"):
        return "maze-alike"
    if key in ("LOC_NE", "LOC_SW"):
        return "repository"
    return "cave"


def label_for(key):
    short = key[4:]
    if short in LABELS:
        return LABELS[short]
    if short.startswith("FOREST"):
        return "Forest"
    if short.startswith("ALIKE"):
        return "Maze"
    if short.startswith("MAZEEND"):
        return "Dead End"
    if short.startswith("DIFFERENT"):
        return "Twisty Maze"
    raise KeyError(f"no label for {key}")


class CaveData:
    def __init__(self, yaml_path):
        data = yaml.safe_load(open(yaml_path))
        self.locs = data["locations"]
        self.names = [n for n, _ in self.locs]
        self.L = dict(self.locs)
        self.index = {n: i for i, n in enumerate(self.names)}
        self._build_rooms()
        self._build_exits()
        self._build_connections()

    # -- forwarders --------------------------------------------------------

    def forwarder(self, n):
        t = self.L[n]["travel"] or []
        return len(t) > 0 and all(len(x["verbs"]) == 0 for x in t)

    def resolve(self, n, depth=0):
        """Follow forwarders. Returns (destination, passed_forwarder)."""
        if depth > 6 or not self.forwarder(n):
            return n, depth > 0
        for t in self.L[n]["travel"]:
            if t["action"][0] == "goto":
                return self.resolve(t["action"][1], depth + 1)
        return None, True

    # -- rooms ---------------------------------------------------------------

    def _build_rooms(self):
        self.rooms = {}       # primary key -> room dict
        self.loc_to_room = {}  # any engine key -> primary key
        diff_n = 0
        for n in self.names:
            if n in SKIP or self.forwarder(n):
                continue
            primary = MERGE.get(n, n)
            self.loc_to_room[n] = primary
            if primary in self.rooms:
                self.rooms[primary]["locs"].append(self.index[n])
                continue
            label = label_for(primary)
            if label == "Twisty Maze":
                diff_n += 1
                label = f"Twisty Maze {diff_n}"
            self.rooms[primary] = {
                "key": primary, "id": self.index[primary], "locs": [self.index[n]],
                "label": label,
                "region": region_for(primary, self.L[primary]["conditions"] or {}),
            }

    # -- exits ---------------------------------------------------------------

    def _build_exits(self):
        """Every way out of every room, to another mapped room."""
        self.exits = []  # (src_key, dst_key, verbs, conditional)
        self.via = set()  # exits that pass through a forwarder (a long crawl etc.)
        special = {  # "special" travel the engine implements in code
            ("LOC_ALCOVE", 1): "LOC_PLOVER", ("LOC_PLOVER", 1): "LOC_ALCOVE",
            ("LOC_SWCHASM", 3): "LOC_NECHASM", ("LOC_NECHASM", 3): "LOC_SWCHASM",
        }
        for n in self.names:
            if n not in self.loc_to_room:
                continue
            src = self.loc_to_room[n]
            for t in self.L[n]["travel"] or []:
                verbs = [v for v in t["verbs"] if v not in MAGIC]
                if not verbs:
                    continue
                kind, target = t["action"][0], t["action"][1]
                if kind == "special":
                    target = special.get((n, target))
                    if target is None:
                        continue
                elif kind != "goto":
                    continue
                dest, via = self.resolve(target)
                if dest is None or dest not in self.loc_to_room:
                    continue  # death, or a message
                dst = self.loc_to_room[dest]
                if via and dst == src:
                    continue  # "you can't go that way" bounced back
                self.exits.append((src, dst, verbs, "cond" in t))
                self.via.add((src, dst, tuple(verbs))) if via else None
        # Moves the engine makes in code rather than its travel table:
        # flying the magic rug between the cliff and the ledge (actions.c).
        self.exits.append(("LOC_CLIFF", "LOC_LEDGE", ["FLY"], True))
        self.exits.append(("LOC_LEDGE", "LOC_CLIFF", ["FLY"], True))

    # -- connections -------------------------------------------------------

    @staticmethod
    def side(verbs):
        """How this end of a connection leaves its room.

        Returns (compass, word): compass is one of n/ne/.../nw or None; word is
        a short label (up/down/in/out/climb/...) or None.
        """
        compass = next((COMPASS[v] for v in verbs if v in COMPASS), None)
        word = next((VERTICAL[v] for v in verbs if v in VERTICAL), None)
        if word is None and compass is None:
            word = next((INOUT[v] for v in verbs if v in INOUT), None)
        if word is None and compass is None:
            word = next((MOVES[v] for v in verbs if v in MOVES), None)
        return compass, word

    @staticmethod
    def drawable(verbs):
        c, w = CaveData.side(verbs)
        return c is not None or w is not None

    def _build_connections(self):
        """One line per pair of rooms joined by a real passage.

        Exits that only name a far-off place ("fork", "debris") are kept for
        the exits list but not drawn, as in hand-drawn maps.
        """
        by_pair = {}
        for src, dst, verbs, cond in self.exits:
            if not self.drawable(verbs):
                continue
            key = (src, dst)
            prev = by_pair.get(key)
            # Prefer a direct exit, then one with a compass direction.
            def rank(v):
                return ((src, dst, tuple(v)) not in self.via, self.side(v)[0] is not None)
            if prev is None or rank(verbs) > rank(prev):
                by_pair[key] = verbs
        conns = {}
        for (src, dst), verbs in by_pair.items():
            k = tuple(sorted((src, dst)))
            c = conns.setdefault(k, {"a": k[0], "b": k[1], "aVerbs": None, "bVerbs": None})
            if src == k[0]:
                c["aVerbs"] = verbs
            else:
                c["bVerbs"] = verbs
            if src == dst:  # maze room that loops back on itself
                c["aVerbs"] = c["bVerbs"] = verbs
        # In the forest and the all-different maze, every room looks alike
        # and the paths between them are a deliberate tangle; lines there
        # would be unreadable. Those rooms are drawn as a block, and the
        # exits list (tap a room in the app) shows where each way leads.
        def hidden(c):
            ra, rb = self.rooms[c["a"]]["region"], self.rooms[c["b"]]["region"]
            return ra == rb and ra in HIDE_INSIDE
        self.connections = [c for c in conns.values() if not hidden(c)]
        for c in self.connections:
            c["portal"] = frozenset({c["a"], c["b"]}) in PORTALS
