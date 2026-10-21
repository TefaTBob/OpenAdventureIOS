#!/usr/bin/env python3
"""
check_map.py — checks the generated map against the running game.

Reads a trace of the player's location at every prompt (produced by
bridge_harness with LOCLOG=1 while replaying upstream's test games) and
verifies that:
  1. every place the engine ever puts the player has a box on the map, and
  2. every move between two places is one the map knows about: a drawn
     line, or an exit listed for the room (maze/forest paths, shortcut
     words, off-page connectors), a magic word, or one of the game's
     teleports (death and reincarnation, the cave closing).

    python3 check_map.py trace.txt
"""
import json
import sys
from pathlib import Path

import yaml

HERE = Path(__file__).parent
MAP = HERE.parent / "OpenAdventure" / "Resources" / "cave_map.json"

m = json.loads(MAP.read_text())
names = [n for n, _ in yaml.safe_load(open(HERE / "adventure.yaml"))["locations"]]
room_of = {l: r["id"] for r in m["rooms"] for l in r["locs"]}
listed = {(r["id"], e["to"]) for r in m["rooms"] for e in r["exits"]}
drawn = set()
for c in m["connections"]:
    if c["aToB"]:
        drawn.add((c["a"], c["b"]))
    if c["bToA"]:
        drawn.add((c["b"], c["a"]))
MAGIC = {("BUILDING", "DEBRIS"), ("DEBRIS", "BUILDING"), ("BUILDING", "Y2"),
         ("Y2", "BUILDING"), ("PLOVER", "Y2"), ("Y2", "PLOVER")}
TELEPORT_TO = {"BUILDING", "START", "NE", "SW"}  # reincarnation; cave closing

problems = []
moves = 0
prev = None
for line in open(sys.argv[1]):
    if line.startswith("FILE"):
        prev = None
        continue
    loc = int(line.split()[1])
    if loc != 0 and loc not in room_of:
        problems.append(f"no box for {names[loc]}")
    if prev and loc and prev != loc and prev in room_of and loc in room_of:
        a, b = room_of[prev], room_of[loc]
        pair = (names[prev][4:], names[loc][4:])
        moves += 1
        if a != b and (a, b) not in drawn and (a, b) not in listed \
                and pair not in MAGIC and pair[1] not in TELEPORT_TO:
            problems.append(f"move not on map: {pair[0]} -> {pair[1]}")
    prev = loc

problems = sorted(set(problems))
print(f"map check: {moves} moves replayed, {len(problems)} problems")
for p in problems:
    print("   ", p)
sys.exit(1 if problems else 0)
