#!/bin/sh
# Runs upstream Open Adventure's regression logs through the iOS engine
# bridge (same code the app links) and compares with upstream's expected
# output. Works on macOS (clang) and Linux (gcc).
#
#   sh Tools/run_engine_tests.sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mktemp -d)
CC=${CC:-cc}
FLAGS="-std=c99 -D_DEFAULT_SOURCE -O1 -I$ROOT/Engine/shim -I$ROOT/Engine/upstream"

$CC $FLAGS "$ROOT"/Engine/wrap/*.c "$ROOT"/Engine/shim/advent_bridge.c \
    "$ROOT"/Tools/bridge_harness.c -lpthread -o "$OUT/harness"
$CC $FLAGS "$ROOT"/Engine/wrap/*.c "$ROOT"/Engine/shim/advent_bridge.c \
    "$ROOT"/Tools/bridge_lifecycle_test.c -lpthread -o "$OUT/lifecycle"

# The save-file tests need doctored saves made by upstream's cheat tool.
printf 'char *readline(const char *p){(void)p;return 0;}\nint add_history(const char *l){(void)l;return 0;}\n' > "$OUT/rl.c"
U="$ROOT/Engine/upstream"
$CC $FLAGS -DVERSION='"1.22"' -o "$OUT/cheat" "$ROOT/Tools/cheat.c" "$U/init.c" "$U/actions.c" \
    "$U/score.c" "$U/misc.c" "$U/saveresume.c" "$U/dungeon.c" "$OUT/rl.c" 2>/dev/null

cd "$ROOT/Tools/upstream-tests"
"$OUT/cheat" -d -900 -o cheat_numdie.adv >/dev/null
"$OUT/cheat" -d -1000 -o cheat_numdie1000.adv >/dev/null
"$OUT/cheat" -d 2000 -o cheat_savetamper.adv >/dev/null
"$OUT/cheat" -v -1337 -o resume_badversion.adv >/dev/null
"$OUT/cheat" -s -1000 -o thousand_saves.adv >/dev/null
"$OUT/cheat" -t -1000 -o thousand_turns.adv >/dev/null
"$OUT/cheat" -l -1000 -o thousand_limit.adv >/dev/null
touch ../main.o  # badmagic.log tries to restore this as a save file

pass=0; fail=0; skip=0
for f in *.log; do
    t=${f%.log}
    opts=$(sed -n 's/#options: //p' "$f")
    r=""
    case "$opts" in
        "") ;;
        "-r "*) r=${opts#-r } ;;
        *) skip=$((skip + 1)); continue ;;  # -l / -o flags aren't used by the app
    esac
    echo "FILE $f" >> "$OUT/trace.txt"
    LOCLOG=1 "$OUT/harness" "$f" $r > "$OUT/$t.out" 2>> "$OUT/trace.raw" || true
    grep '^LOC' "$OUT/trace.raw" >> "$OUT/trace.txt" || true
    : > "$OUT/trace.raw"
    # The bridge echoes the in-game "File name:" prompt like a terminal
    # would; upstream's piped tests don't. Ignore just that.
    grep -v '^File name: ' "$OUT/$t.out" > "$OUT/$t.norm" || true
    grep -v '^File name: ' "$t.chk" > "$OUT/$t.want" || true
    if diff -qB "$OUT/$t.want" "$OUT/$t.norm" >/dev/null; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1)); echo "FAIL $t"
    fi
done
rm -f ../main.o *.adv scratch.tmp
echo "engine regression: $pass passed, $fail failed, $skip skipped"
"$OUT/lifecycle"
# The map must agree with the game (needs Python 3 + PyYAML).
python3 "$ROOT/Tools/check_map.py" "$OUT/trace.txt" || fail=$((fail + 1))
rm -rf "$OUT"
[ "$fail" -eq 0 ]
