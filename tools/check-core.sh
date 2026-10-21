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
    say "==> building the Amiberry core"
    cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DUAE4ARM_CORE_LIBRARY=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        > /tmp/check-core-configure.log 2>&1 \
        || { fail "configure (see /tmp/check-core-configure.log)"; exit 1; }
    cmake --build build-linux -j"$(nproc)" > /tmp/check-core-build.log 2>&1 \
        || { fail "build (see /tmp/check-core-build.log)"; exit 1; }

    # The Copperline core is Rust; its harness is the smoke binary beside
    # the crate, which drives the same lifecycle the phone hosts do -- run,
    # publish frames, quit, run again in one process.
    if cargo --version > /dev/null 2>&1; then
        say "==> building the Copperline core"
        cargo build --release --manifest-path native/copperline_ffi/Cargo.toml \
            > /tmp/check-core-copperline-build.log 2>&1 \
            || fail "copperline build (see /tmp/check-core-copperline-build.log)"
    else
        say "skip: no cargo - the Copperline core is not built or checked"
    fi
fi

CORE=build-linux/libuae4arm.so
[ -f "$CORE" ] || { fail "no core at $CORE"; exit 1; }
COPPER=native/copperline_ffi/target/release/libcopperline_ffi.so
HAVE_COPPER=0
[ -f "$COPPER" ] && HAVE_COPPER=1

WORK=$(mktemp -d /tmp/check-core.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

cc tools/core-twice.c  -ldl -lpthread -o "$WORK/core-twice"  || exit 1
cc tools/core-again.c  -ldl -lpthread -o "$WORK/core-again"  || exit 1

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

# ---- scenarios: Amiberry ---------------------------------------------------
# Each one is a former bug. Comments name the corpse.
#
# Test media: any two WHDLoad archives from the library. The scenarios need
# real archives because the archive-mount path is where the statics bite.
LHA_DIR="${AMIGA_LHA_DIR:-$HOME/Amiga-Retro/LHA}"
mapfile -t GAMES < <(ls "$LHA_DIR"/*.lha 2>/dev/null | head -2)
if [ "${#GAMES[@]}" -lt 2 ]; then
    say "skip: needs two .lha archives in $LHA_DIR (set AMIGA_LHA_DIR)"
else
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
fi # two .lha archives present

# ---- scenarios: Copperline -------------------------------------------------
# The same lifecycle - run, frames, quit, run again in one process - through
# the uae4arm_host_* surface on the Rust core. No media needed: the bundled
# AROS boots with no Kickstart. COPPERLINE_AROS_DIR points the asset search
# at the source tree because the harness binary lives in a temp dir.
if [ "$HAVE_COPPER" -eq 1 ]; then
    cc native/copperline_ffi/smoke_host.c \
        -L native/copperline_ffi/target/release -lcopperline_ffi -lpthread \
        -o "$WORK/smoke_host" \
        || { fail "copperline smoke build"; exit 1; }
    COPPERLINE_AROS_DIR="$PWD/copperline/assets/aros" \
        LD_LIBRARY_PATH=native/copperline_ffi/target/release \
        timeout 180 "$WORK/smoke_host" > "$WORK/copperline.log" 2>&1
    if grep -q "HOST SMOKE OK" "$WORK/copperline.log"; then
        pass "copperline run-quit-run (frames, pads, session, recent.txt)"
    else
        fail "copperline smoke (log: /tmp/check-core-copperline.log)"
        cp "$WORK/copperline.log" /tmp/check-core-copperline.log
    fi
else
    say "skip: no Copperline core at $COPPER"
fi

# ---- verdict ---------------------------------------------------------------

if [ "$failures" -eq 0 ]; then
    say "${GREEN}==> core checks all green${PLAIN}"
else
    say "${RED}==> $failures failure(s)${PLAIN}"
fi
exit "$failures"
