# Testing

Every event is tested in game by a script, in single player and in multiplayer
(server and client). Run it before every upload and after every game update.

## Run it

Close the game first, then:

```bash
test/run.sh sp
test/run.sh mp
```

Each command opens the game in a window, starts a world or joins a local
server on its own, runs every step, quits and prints the result. Don't touch the
window while it runs (a few minutes). Each run has its own game folder in
`~/Zomboid-vetest` (`-cachedir`), so your normal saves and mods are never touched.

- `test/run.sh sp --guided` / `mp --guided`: after the automatic steps,
  yellow notes over the player ask you to drive: forward, reverse, onto the
  grass and back. That covers going offroad and back on the road, which the
  key presses can't aim for.
- `test/run.sh sp --only-guided`: just the car and those guided steps, no
  automatic steps (about a minute).
- `test/run.sh report`: prints the last results again.
- `test/run.sh clean`: deletes `~/Zomboid-vetest`.

Needs an unlocked X11 desktop. After loading, the game waits for a mouse click
("click to start"), and no Lua or command line option skips it. `test/click.py`
clicks the middle of the game window once, then puts your pointer back. It
refuses to click while the screen is locked, and the run waits until you unlock
it. A new test folder starts from a copy of your `~/Zomboid/options.ini`, so it
keeps your Terms of Service acceptance instead of stopping on that screen.
`run.sh` also sets `focusloss=false` (so the game keeps running when you click
elsewhere) and turns off the Survival Guide and the tutorial popups.

Driving has no Lua way either (the game reads the real keyboard), so for the
drive steps the test asks `run.sh` to hold W, then S, in the game window
(`click.py ... keys`). The game window takes the focus for those few seconds:
don't type elsewhere meanwhile. If the keys don't reach the game, those steps
end as MANUAL.

The test turns off the Lua debugger popup (in `-debug` it stops the whole game on
any Lua error; the error still goes to `console.txt`). Short game freezes
(saving, loading chunks) don't count toward a step's timeout.

The test mod (`test/VehicleEventsTest`) is never uploaded. `run.sh` copies it
next to the API in the test folders.

## What it does

1. Finds a street near the player and spawns a police car there
   (`Base.CarLightsPolice`: lightbar, siren, radio, heater, trunk, 4 doors).
2. For each step (about 80): waits until no event fired for 1.5 s, changes one
   thing on the car, then waits for the events the README promises.
3. Checks each event:
   - fired on the right side (player events on the client, world events on the
     server, both in single player);
   - fired once, not twice;
   - has the right arguments: the player, the test car or the right part, and
     the new / old values (seat numbers, items, engine states, weights...).
4. Also tests:
   - the event names match the README, both ways;
   - the sandbox translation shows (and no `%%` leaks);
   - no listener, no event; and no stale event when listeners come back;
   - reloading the API files while seated doesn't fire `Entered` again;
   - getting into a running car only fires `Entered`;
   - chunk unload (`Unloaded`), a car loading back in fires nothing;
   - dying in the car fires `Exited`.
5. Ends with a coverage list: every event and side from the README is PASS,
   FAIL or MANUAL (needs `--guided`).

Where the change is made: the car side (engine, lights, parts, fuel...) on the
server in MP, like the game does; the player's own actions (seats, radio,
cruise control, driving with W / S and flipping the car) on the client.

## Results

| File | What |
| --- | --- |
| `~/Zomboid-vetest/sp/Lua/VehicleEventsTest_result.txt` | single player summary, every non PASS line |
| `~/Zomboid-vetest/sp/Lua/VehicleEventsTest_sp.log` | every step and every event with its arguments |
| `~/Zomboid-vetest/client/Lua/VehicleEventsTest_result.txt` | MP summary (client and server events) |
| `~/Zomboid-vetest/client/Lua/VehicleEventsTest_client.log` | MP, client side |
| `~/Zomboid-vetest/server/Lua/VehicleEventsTest_server.log` | MP, server side |

`run.sh` also searches each `console.txt` for Lua errors: an error inside a
listener is only logged, the event still counts as fired, so any error there
fails the run.

Statuses: `PASS`; `FAIL`; `WARN` (an event nobody expected fired, look at
it); `MANUAL` (no code can do it, or the automatic try didn't work: run
`--guided`).

## Not covered

- Split screen (needs a second controller).
- Loading a save while sitting in a car fires `Entered`.
