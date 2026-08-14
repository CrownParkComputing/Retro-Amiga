#!/usr/bin/env bash
# Integration tests for the emulator core, run on Linux before anything goes
# near a device. Every scenario here is a bug that once cost a device
# round-trip to find; the point of the file is that the next one does not.
#
#   tools/check-core.sh            build the Linux core and run every scenario
#   SKIP_BUILD=1 tools/check-core.sh   reuse the existing build
#
# The core is exercised the way the phone hosts drive it: dlopened, run,
# quit from another thread, run again. Software rendering, because the
# NVIDIA driver crashes on the second GL context in ways devices do not.

set -u
cd "$(dirname "$0")/.."

RED=$'\033[31m'; GREEN=$'\033[32m'; PLAIN=$'\033[0m'
failures=0

say()  { printf '%s\n' "$*"; }
pass() { say "${GREEN}pass${PLAIN}  $*"; }
fail() { say "${RED}FAIL${PLAIN}  $*"; failures=$((failures + 1)); }

# ---- build ----------------------------------------------------------------

if [ -z "${SKIP_BUILD:-}" ]; then
    say "==> building the Linux core"
    cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DUAE4ARM_CORE_LIBRARY=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        > /tmp/check-core-configure.log 2>&1 \
        || { fail "configure (see /tmp/check-core-configure.log)"; exit 1; }
    cmake --build build-linux -j"$(nproc)" > /tmp/check-core-build.log 2>&1 \
        || { fail "build (see /tmp/check-core-build.log)"; exit 1; }
fi

CORE=build-linux/libuae4arm.so
[ -f "$CORE" ] || { fail "no core at $CORE"; exit 1; }

WORK=$(mktemp -d /tmp/check-core.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

cc tools/core-twice.c  -ldl -lpthread -o "$WORK/core-twice"  || exit 1
cc tools/core-again.c  -ldl -lpthread -o "$WORK/core-again"  || exit 1

# Test media: any two WHDLoad archives from the library. The scenarios need
# real archives because the archive-mount path is where the statics bite.
LHA_DIR="${AMIGA_LHA_DIR:-$HOME/Amiga-Retro/LHA}"
mapfile -t GAMES < <(ls "$LHA_DIR"/*.lha 2>/dev/null | head -2)
if [ "${#GAMES[@]}" -lt 2 ]; then
    say "skip: needs two .lha archives in $LHA_DIR (set AMIGA_LHA_DIR)"
    exit 0
fi

run() { # name, expected-runs, harness args...
    local name=$1 expected=$2; shift 2
    local log="$WORK/$name.log"
    LIBGL_ALWAYS_SOFTWARE=1 timeout 180 "$@" > "$log" 2>&1
    local status=$?
    local returned
    returned=$(grep -cE "harness: ===== run . returned 0" "$log")
    if [ "$status" -eq 0 ] && [ "$returned" -eq "$expected" ]; then
        pass "$name"
    else
        fail "$name (exit $status, $returned/$expected clean runs)"
    fi
    # Kept win or lose: the assertions below read these, and a failed
    # assertion with a deleted log is a bug report about nothing.
    cp "$log" "/tmp/check-core-$name.log"
}

# ---- scenarios -------------------------------------------------------------
# Each one is a former bug. Comments name the corpse.
#
# JIT off, to match the hosts this stands in for: iOS cannot JIT and Android
# starts each game in a fresh process, so no shipped host ever re-enters the
# JIT in one process. The Linux build does, and its translation cache does
# not survive the natmem base moving between runs - a real bug, but one only
# this harness can hit (tracked; found by this very file on its first run).
JITOFF=(-s cachesize=0)

# SDL teardown: the second run used to hang before SDL was kept alive on iOS;
# on Linux SDL restarts, so this covers the plain restart path.
run same-game-twice 2 "$WORK/core-twice" "$CORE" --log "${JITOFF[@]}" --autoload "${GAMES[0]}" -G

# The command-line guard: run 2 used to boot default hardware because
# parse_cmdline refused to run twice. Different args flush that out.
# The archive-volume list: run 2 used to crash (or spin, on iOS) walking
# freed volumes from run 1's archives.
run different-games 2 "$WORK/core-again" "$CORE" \
    --log "${JITOFF[@]}" --autoload "${GAMES[0]}" -G -- --log "${JITOFF[@]}" --autoload "${GAMES[1]}" -G

# Quit must bring the filesystem units down and the run must say so - the
# death-handshake breadcrumbs double as the assertion that cleanup ran.
if grep -q "filesys: cleanup done" "$WORK/same-game-twice.log"; then
    pass "quit runs the filesystem cleanup"
else
    fail "quit did not log filesystem cleanup"
fi

# Run 2 must actually parse its command line - the silent version of the
# cmdline bug is a second run with no parameters logged.
if [ "$(grep -c "Command line parameters" "$WORK/different-games.log")" -ge 2 ]; then
    pass "both runs parse their command line"
else
    fail "run 2 lost its command line"
fi

# ---- verdict ---------------------------------------------------------------

if [ "$failures" -eq 0 ]; then
    say "${GREEN}==> core checks all green${PLAIN}"
else
    say "${RED}==> $failures failure(s)${PLAIN}"
fi
exit "$failures"
