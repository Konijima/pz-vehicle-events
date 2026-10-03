#!/bin/bash
# Automatic in-game test of every Vehicle Events API event, single player and multiplayer.
# Each run has its own game folder under ~/Zomboid-vetest (-cachedir), with its own copy of the mods,
# so your normal ~/Zomboid saves and mods are never touched. Close the game first.
#
#   test/run.sh sp [--guided]   new single player world, runs every step, quits, prints the result
#   test/run.sh mp [--guided]   local no-Steam server + one client (admin), same thing, both sides checked
#   --only-guided               just the car and the guided steps (no automatic steps)
#   test/run.sh report          prints the last results and the errors found in the consoles
#   test/run.sh clean           deletes ~/Zomboid-vetest (worlds, accounts, logs)
#
# --guided: after the automatic steps, on-screen notes ask you to drive offroad and back.
# The first mp run creates the admin's character on its own (default character).
#
# Results: ~/Zomboid-vetest/<sp|client|server>/Lua/VehicleEventsTest_*.log and VehicleEventsTest_result.txt

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
GAME="$HOME/.local/share/Steam/steamapps/common/ProjectZomboid/projectzomboid"
ROOT="$HOME/Zomboid-vetest"
NAME="vetest"
PORT=16261
ADMIN_PASS="${VET_ADMIN_PASS:-vetest}"
RUN_TIMEOUT=1500   # seconds before a run is called stuck

GUIDED=""
for a in "$@"; do
    [ "$a" = "--guided" ] && GUIDED=" guided"
    [ "$a" = "--only-guided" ] && GUIDED=" only-guided"
done

copy_mods() {
    local dir="$1/mods"
    mkdir -p "$dir"
    rm -rf "$dir/VehicleEvents" "$dir/VehicleEventsTest"
    # copies, not symlinks: the game builds broken paths from symlinked mods
    cp -r "$REPO/Contents/mods/VehicleEvents" "$dir/"
    cp -r "$REPO/test/VehicleEventsTest" "$dir/"
    # without this marker the first start of a new folder turns every mod off (ZomboidFileSystem.java:1338)
    echo "If this file does not exist, default.txt will be reset to empty (no mods active)." > "$dir/reset-mods-42_00.txt"
    # enabled at the main menu, so the test can start the game on its own
    cat > "$dir/default.txt" <<EOF
VERSION = 1,

mods
{
    mod = \\VehicleEvents,
    mod = \\VehicleEventsTest,
}

maps
{
}
EOF
}

# windowed 1280x720 (the game rewrites options.ini on exit, so set it before every start).
# A new folder starts from your own ~/Zomboid/options.ini, so it keeps your Terms of Service
# acceptance (termsOfServiceVersion) instead of stopping on that screen. It copies your own choice, so run it only if you accepted them.
windowed() {
    local ini="$1/options.ini"
    mkdir -p "$1"
    [ -f "$ini" ] || cp "$HOME/Zomboid/options.ini" "$ini"
    grep -q "^termsOfServiceVersion=" "$ini" || echo "termsOfServiceVersion=1" >> "$ini"
    sed -i "s/^termsOfServiceVersion=.*/termsOfServiceVersion=1/" "$ini"
    sed -i 's/^fullScreen=.*/fullScreen=false/; s/^width=.*/width=1280/; s/^height=.*/height=720/' "$ini"
    # keep running when the window loses focus (focusloss=true pauses single player)
    sed -i 's/^focusloss=.*/focusloss=false/' "$ini"
    # the survival guide opens on a new game and pauses it, the tutorials pop up mid test
    sed -i 's/^showSurvivalGuide=.*/showSurvivalGuide=false/; s/^showFirstTimeSearchTutorial=.*/showFirstTimeSearchTutorial=false/; s/^showFirstTimeSneakTutorial=.*/showFirstTimeSneakTutorial=false/' "$ini"
}

java_env() {
    cd "$GAME" || exit 1
    export PATH="$GAME/jre64/bin:$PATH"
    export LD_LIBRARY_PATH="$GAME/natives:$GAME:$GAME/jre64/lib:$GAME/jre64/lib/amd64:${LD_LIBRARY_PATH:-}"
}
JAVA_ARGS=(-cp ./:./projectzomboid.jar --enable-native-access=ALL-UNNAMED
    --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED -XX:+UseZGC -XX:-OmitStackTraceInFastThrow
    -Dzomboid.steam=0 -Dzomboid.znetlog=1 -Djava.library.path=./:./natives/ -Djava.security.egd=file:/dev/urandom)

start_client() {
    local dir="$1"
    rm -f "$dir/console.txt"
    windowed "$dir"
    ( java_env
      XMODIFIERS= LD_PRELOAD="${LD_PRELOAD:-}:libjsig.so:libPZXInitThreads64.so" \
        exec java "${JAVA_ARGS[@]}" -Djava.awt.headless=true -Xmx3072m zombie/gameStates/MainScreenState \
        -nosteam -debug -cachedir="$dir" >"$dir/client-stdout.log" 2>&1 ) &
    CLIENT_PID=$!
}

# the "click to start" screen after loading only reacts to a real mouse click: click.py does it,
# only once the console says loading is done and until the test has started (mode file read)
click_to_start() {
    local dir="$1" pid="$2"
    (
        # console.txt was deleted before the start, so this line is from this run
        until grep -q "game loading took" "$dir/console.txt" 2>/dev/null \
            && [ -s "$dir/Lua/VehicleEventsTest_mode.txt" ]; do
            kill -0 "$pid" 2>/dev/null || exit 0
            sleep 2
        done
        # keeps trying while the screen is locked (click.py refuses to click then)
        for _ in $(seq 1 150); do
            sleep 4
            kill -0 "$pid" 2>/dev/null || exit 0
            [ -s "$dir/Lua/VehicleEventsTest_mode.txt" ] || exit 0
            python3 "$REPO/test/click.py" "$pid"
        done
    ) &
}

# driving has no Lua way (the game reads the real keyboard): the test writes
# "w 1500 none 500 s 2000" (key, ms, ...) in VehicleEventsTest_keys.txt, this holds those keys
# in the game window and deletes the file when done
key_presser() {
    local dir="$1" pid="$2"
    local file="$dir/Lua/VehicleEventsTest_keys.txt"
    (
        while kill -0 "$pid" 2>/dev/null; do
            if [ -s "$file" ]; then
                local keys
                keys=$(head -1 "$file")
                # shellcheck disable=SC2086
                python3 "$REPO/test/click.py" "$pid" keys $keys >>"$dir/keys.log" 2>&1
                rm -f "$file"
            fi
            sleep 0.3
        done
    ) &
}

# waits for DONE in a result file, or the game closing, or the timeout
wait_done() {
    local file="$1" pid="$2" start=$SECONDS
    while kill -0 "$pid" 2>/dev/null; do
        if grep -q "^DONE" "$file" 2>/dev/null; then
            # the test quits the game itself a few seconds later
            for _ in $(seq 1 60); do kill -0 "$pid" 2>/dev/null || return 0; sleep 1; done
            kill "$pid" 2>/dev/null
            return 0
        fi
        if [ $((SECONDS - start)) -gt $RUN_TIMEOUT ]; then
            echo "!! no result after ${RUN_TIMEOUT}s, stopping the game"
            kill "$pid" 2>/dev/null
            return 1
        fi
        sleep 2
    done
}

# Lua errors are only logged, an event still counts as fired: any of these fails the run
scan_console() {
    local label="$1" file="$2"
    [ -f "$file" ] || { echo "-- $label: no $file"; return; }
    local hits
    hits=$(grep -nE "STACK TRACE|ERROR: Formatting|\[VehicleEvents\] ERROR|Exception thrown|LuaException|attempted index|Callframe" "$file" \
        | grep -vE "VehicleEventsTest_auto|visitFileFailed|IsoPropertyType" | head -40)
    if [ -n "$hits" ]; then
        echo "-- $label console errors (FAIL):"
        echo "$hits"
    else
        echo "-- $label console: no Lua errors"
    fi
}

report() {
    for side in sp client server; do
        local dir="$ROOT/$side"
        [ -d "$dir" ] || continue
        echo "==================== $side"
        if [ "$side" != server ] && [ -f "$dir/Lua/VehicleEventsTest_result.txt" ]; then
            cat "$dir/Lua/VehicleEventsTest_result.txt"
        fi
        [ "$side" = server ] && [ -f "$dir/Lua/VehicleEventsTest_server.log" ] && tail -3 "$dir/Lua/VehicleEventsTest_server.log"
        if [ "$side" = server ]; then scan_console "$side" "$dir/server-console.txt"
        else scan_console "$side" "$dir/console.txt"; fi
    done
}

case "${1:-}" in
    sp)
        dir="$ROOT/sp"
        copy_mods "$dir"
        mkdir -p "$dir/Lua"
        rm -f "$dir/Lua/VehicleEventsTest_"*
        echo "sp$GUIDED" > "$dir/Lua/VehicleEventsTest_auto.txt"
        start_client "$dir"
        click_to_start "$dir" "$CLIENT_PID"
        key_presser "$dir" "$CLIENT_PID"
        echo "single player test running (game pid $CLIENT_PID), log: $dir/Lua/VehicleEventsTest_sp.log"
        wait_done "$dir/Lua/VehicleEventsTest_result.txt" "$CLIENT_PID"
        report
        ;;
    mp)
        if ss -ltnu | grep -qE ":$PORT\b"; then echo "port $PORT is in use, stop the other server first"; exit 1; fi
        sdir="$ROOT/server"
        cdir="$ROOT/client"
        copy_mods "$sdir"
        copy_mods "$cdir"
        mkdir -p "$sdir/Server" "$sdir/Lua" "$cdir/Lua"
        rm -f "$sdir/Lua/VehicleEventsTest_"* "$cdir/Lua/VehicleEventsTest_"*
        # a new world each run: cars left by the last run (same street) would get in the way
        rm -rf "$sdir/Saves/Multiplayer/$NAME" "$cdir/Saves/Multiplayer"
        ini="$sdir/Server/$NAME.ini"
        if [ ! -f "$ini" ]; then
            # the server adds every missing option with its default on first start
            cat > "$ini" <<EOF
Mods=VehicleEvents;VehicleEventsTest
WorkshopItems=
Map=Muldraugh, KY
Open=true
Public=false
Password=
PVP=false
UPnP=false
DefaultPort=$PORT
UDPPort=$((PORT + 1))
AntiCheatSpeed=4
AntiCheatNoClip=4
AntiCheatPlayer=4
AntiCheatPacketException=4
AntiCheatPermission=4
AntiCheatSafety=4
EOF
        fi
        if [ ! -f "$sdir/Server/${NAME}_SandboxVars.lua" ]; then
            # no zombies; the rest is filled with defaults by the server
            cat > "$sdir/Server/${NAME}_SandboxVars.lua" <<EOF
SandboxVars = {
    VERSION = 6,
    Zombies = 6,
}
EOF
        fi
        # stdin kept open (the server reads console commands from it)
        ( java_env
          tail -f /dev/null | LD_PRELOAD="${LD_PRELOAD:-}:libjsig.so" exec java "${JAVA_ARGS[@]}" -Djava.awt.headless=true \
            -Xms512m -Xmx2048m zombie/network/GameServer \
            -nosteam -cachedir="$sdir" -servername "$NAME" -adminusername admin -adminpassword "$ADMIN_PASS" \
            >"$sdir/server-stdout.log" 2>&1 ) &
        SERVER_PID=$!
        echo "server starting (pid $SERVER_PID)"
        for _ in $(seq 1 300); do
            grep -q "SERVER STARTED" "$sdir/server-stdout.log" 2>/dev/null && break
            kill -0 "$SERVER_PID" 2>/dev/null || { echo "server died, see $sdir/server-stdout.log"; tail -20 "$sdir/server-stdout.log"; exit 1; }
            sleep 1
        done
        echo "server started"
        echo "mp admin $ADMIN_PASS $PORT$GUIDED" > "$cdir/Lua/VehicleEventsTest_auto.txt"
        start_client "$cdir"
        click_to_start "$cdir" "$CLIENT_PID"
        key_presser "$cdir" "$CLIENT_PID"
        echo "client running (pid $CLIENT_PID), log: $cdir/Lua/VehicleEventsTest_client.log"
        wait_done "$cdir/Lua/VehicleEventsTest_result.txt" "$CLIENT_PID"
        # the client sends /quit when done; give the server time to save, then stop it
        for _ in $(seq 1 60); do kill -0 "$SERVER_PID" 2>/dev/null || break; sleep 1; done
        kill "$SERVER_PID" 2>/dev/null
        wait "$SERVER_PID" 2>/dev/null
        report
        ;;
    report)
        report
        ;;
    clean)
        rm -rf "$ROOT"
        echo "deleted $ROOT"
        ;;
    *)
        sed -n '2,15p' "$0"
        ;;
esac
