# Vehicle Events API

*Lua events for everything cars do in Project Zomboid, Build 42.*

---

Cars in Project Zomboid live a quiet life. A player presses W and the engine
turns over. An engine coughs and dies on an empty tank. A window shatters, an
alarm starts to wail, a trailer is hooked up behind a pickup. All of it happens
in the game's Java code, and Lua is told none of it.

This mod listens for you. It watches the cars, notices when something about
them changes, and fires an event your mod can hook into, the same way you hook
into any other game event.

It is tested in the real game, every event, in single player and in
multiplayer on a dedicated server ([how](#how-it-was-tested)).

Mod ID `VehicleEvents`, Workshop ID `3812280978`:
[subscribe on the Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3812280978).

---

## Getting started

### Ask for it, don't copy it

Your players install Vehicle Events API next to your mod. Please don't copy its
files into your own: two copies of the same file fight each other, and yours
stops getting fixes.

Add one line to your `mod.info`. The game then loads the API first, and refuses
to load your mod without it:

```
require=\VehicleEvents
```

On your Steam Workshop page, also add
[Vehicle Events API](https://steamcommunity.com/sharedfiles/filedetails/?id=3812280978)
as a **Required item** (*Add/Remove Required Items* in the owner controls).
Then Steam offers to subscribe to it along with your mod, which `mod.info`
alone doesn't do. Servers list it like any mod: `VehicleEvents` in `Mods=`,
`3812280978` in `WorkshopItems=`.

### Listen

```lua
-- media/lua/client/MyMod.lua
local function onEngineStarted(player, vehicle)
    print("vroom")
end

Events.VehicleEvents_OnPlayerVehicleEngineStarted.Add(onEngineStarted)
```

That's all. Files in `client/` and `server/` load after the API on their own. A
file in `shared/` needs `require "VehicleEvents"` at the top.

Start the game with `-debug` and every event prints to the console as it fires,
which is the quickest way to see what you can use.

---

## Two points of view

Every event exists twice, because there are two ways to look at a car.

**The player's view.** These events follow the car a local player is sitting
in, any seat, and nothing else. They run in the player's own game, so your code
goes in `client/`. Their names start with `VehicleEvents_OnPlayerVehicle`, and
the first parameter is the player.

**The world's view.** These events follow every loaded car, even the empty ones
parked down the street. They run where the world lives, so your code goes in
`server/`. Their names start with `VehicleEvents_OnVehicle`, and the first
parameter is the car.

| | Player events | World events |
|---|---|---|
| Single player | yes | yes |
| Multiplayer client | yes | no |
| Multiplayer server | no | yes |

In single player your game is both, so a car you drive fires each change twice,
once from each point of view. Pick the one that fits what you're doing.

Player events check every tick. World events check every loaded car once a
second (a [setting](#settings)). A few events that rarely need to be instant,
marked 🐢 below, are checked less often: every second for the player, every
fifth pass for the world.

---

## The events

Put `VehicleEvents_OnPlayerVehicle` or `VehicleEvents_OnVehicle` in front of a
name: `EngineStarted` becomes `VehicleEvents_OnPlayerVehicleEngineStarted`.

A few things hold for all of them:

- On / off pairs, like `EngineStarted` / `EngineStopped`, also receive the new
  and old value (`true`, `false`) after the parameters shown. You can ignore
  them.
- Player events about a part get the part instead of the car (the game allows
  four parameters). `part:getVehicle()` gives you the car, and `part:getId()`
  tells you which part it is: `DoorFrontLeft`, `TrunkDoor`, `EngineDoor`...
- Seat `0` is the driver.
- A dash means that point of view doesn't have the event.

### Getting in and out

| Event | When | Player | World |
|---|---|---|---|
| `Entered` | Someone gets in | `player, vehicle, seat` | `vehicle, character, seat` |
| `Exited` | Someone gets out, dying included | `player, vehicle, seat` | `vehicle, character, seat` |
| `SeatChanged` | Someone changes seat | `player, vehicle, newSeat, oldSeat` | `vehicle, character, newSeat, oldSeat` |
| `BecameOccupied` / `BecameEmpty` | The first one gets in / the last one leaves | — | `vehicle` |
| `FirstOpened` | A player opens one of its doors for the first time | — | `vehicle` |

The last two are world only: a player can't be inside a car at the moment it
was still empty.

### Engine and power

| Event | When | Player | World |
|---|---|---|---|
| `EngineStarted` / `EngineStopped` | The engine runs / stops (turned off, stalled, out of fuel) | `player, vehicle` | `vehicle` |
| `EngineStateChanged` | The engine moves to another state | `player, vehicle, new, old` | `vehicle, new, old` |
| `FuelEmpty` / `FuelRefilled` | The tank runs dry / has fuel again | `player, vehicle` | `vehicle` |
| `FuelLow` / `FuelNoLongerLow` | Fuel drops below 25% / climbs back over 30% | `player, vehicle` | `vehicle` |
| `PowerLost` / `PowerRestored` | No power (battery dead or gone) / power again | `player, vehicle` | `vehicle` |
| `BatteryLow` / `BatteryNoLongerLow` | Charge drops below 20% / climbs back over 25% | `player, vehicle` | `vehicle` |
| `BrokeDown` / `BecameDriveable` 🐢 | The car can't drive anymore / can again | `player, vehicle` | `vehicle` |

The engine states are `Idle`, `Starting`, `RetryingStarting`, `StartingSuccess`,
`StartingFailed`, `Running`, `Stalling` and `ShuttingDown`; compare them with
`tostring(new) == "Running"`. A start that fails only shows up here, since
`EngineStarted` waits for an engine that really runs.

### Driving

| Event | When | Player | World |
|---|---|---|---|
| `StartedMoving` / `StoppedMoving` | Ground speed goes over 2 km/h / under 0.5 km/h | `player, vehicle` | `vehicle` |
| `Flipped` / `BackOnWheels` | It ends up on its roof or side / back on its wheels | `player, vehicle` | `vehicle` |
| `GearChanged` | The gear changes: `-1` is reverse, `0` neutral | `player, vehicle, newGear, oldGear` | — |
| `ShiftedIntoReverse` / `ShiftedOutOfReverse` | Into / out of reverse, moving or not | `player, vehicle` | — |
| `CruiseControlTurnedOn` / `CruiseControlTurnedOff` | Cruise control on / off | `player, vehicle` | — |
| `WentOffroad` / `BackOnRoad` 🐢 | Leaves the road / gets back on it | `player, vehicle` | — |

### Lights and sounds

| Event | When | Player | World |
|---|---|---|---|
| `HeadlightsTurnedOn` / `HeadlightsTurnedOff` | Headlights on / off | `player, vehicle` | `vehicle` |
| `LightbarTurnedOn` / `LightbarTurnedOff` | Police lights on / off | `player, vehicle` | `vehicle` |
| `SirenTurnedOn` / `SirenTurnedOff` | Siren on / off | `player, vehicle` | `vehicle` |
| `RadioTurnedOn` / `RadioTurnedOff` | Radio on / off | `player, vehicle` | `vehicle` |
| `HeaterTurnedOn` / `HeaterTurnedOff` | Heater or AC on / off | `player, vehicle` | `vehicle` |
| `HornStarted` / `HornStopped` | Horn pressed / released | `player, vehicle` | — |

### Alarm, keys and locks

| Event | When | Player | World |
|---|---|---|---|
| `AlarmStartedRinging` / `AlarmStoppedRinging` | The alarm starts / stops sounding | `player, vehicle` | `vehicle` |
| `AlarmArmed` / `AlarmDisarmed` | The alarm is armed / disarmed | `player, vehicle` | `vehicle` |
| `IgnitionKeyInserted` / `IgnitionKeyRemoved` | Key in / out of the ignition | `player, vehicle` | — |
| `Hotwired` / `HotwireRemoved` | Hotwired / not anymore | `player, vehicle` | `vehicle` |
| `HotwireBroken` / `HotwireRepaired` | The hotwire breaks / works again | `player, vehicle` | `vehicle` |
| `AnyDoorLocked` / `AllDoorsUnlocked` | One seat door locks / none is locked anymore | `player, vehicle` | `vehicle` |
| `TrunkLocked` / `TrunkUnlocked` | Trunk locked / unlocked | `player, vehicle` | `vehicle` |

### Doors and windows

| Event | When | Player | World |
|---|---|---|---|
| `DoorOpened` / `DoorClosed` | A door, the trunk or the hood opens / closes | `player, part` | `vehicle, part` |
| `DoorLocked` / `DoorUnlocked` | One door locks / unlocks | `player, part` | `vehicle, part` |
| `WindowOpened` / `WindowClosed` | A window rolls down / up | `player, part` | `vehicle, part` |
| `WindowSmashed` / `WindowRepaired` | A window breaks / is fixed | `player, part` | `vehicle, part` |

### Parts and tires

| Event | When | Player | World |
|---|---|---|---|
| `PartInstalled` / `PartRemoved` 🐢 | A part goes in / comes out | `player, part, newItem, oldItem` | `vehicle, part, newItem, oldItem` |
| `PartConditionChanged` 🐢 | A part's condition changes (0 to 100) | `player, part, new, old` | `vehicle, part, new, old` |
| `TireWentFlat` / `TireInflated` 🐢 | A tire loses all its air / gets some back | `player, part` | `vehicle, part` |
| `TireMissing` / `AllTiresInstalled` 🐢 | A tire is missing / they are all back | `player, vehicle` | `vehicle` |

### Cargo and towing

| Event | When | Player | World |
|---|---|---|---|
| `CargoChanged` 🐢 | Items go in or out | `player, vehicle, newWeight, oldWeight` | `vehicle, newWeight, oldWeight` |
| `AnimalsChanged` | Animals go in or out of a trailer | — | `vehicle, newSize, oldSize` |
| `StartedTowing` / `StoppedTowing` | Starts / stops towing another car | `player, vehicle, newTowed, oldTowed` | `vehicle, newTowed, oldTowed` |
| `StartedBeingTowed` / `StoppedBeingTowed` | Gets hooked to / let go by another car | `player, vehicle, newTower, oldTower` | `vehicle, newTower, oldTower` |
| `Unloaded` | The car leaves the world (unloaded or deleted) | — | `vehicle` |

`AnimalsChanged` is world only because no vanilla car with seats carries
animals.

---

## Things worth knowing

**Events describe changes, not states.** Getting into a car fires `Entered` and
nothing else: if the engine was already running, you won't get `EngineStarted`.
Ask the car directly when you need its state. In the same spirit, a car that
loads in as you drive up fires nothing; a car that unloads fires `Unloaded`.
Loading a save while sitting in a car does fire `Entered`.

**Some vanilla behaviour shows through.** The game clears the "armed" flag when
an alarm goes off, so `AlarmDisarmed` fires then too. `FirstOpened` follows the
game's own "previously entered" flag, which arming the alarm resets, so it can
fire again later. When a driven car is hooked behind an empty one, the game
swaps them at once so the driven car does the towing: you'll see
`StartedBeingTowed`, then `StoppedBeingTowed` and `StartedTowing` a moment
later. Cruise control is only known to the driver's game, so its events only
fire there.

**Timing has limits.** A world check that comes once a second can miss
something that lasts less than that. Two changes in a row between checks look
like one: swapping a part for another fires `PartInstalled` again without
`PartRemoved` first. In multiplayer, player events come a moment late, because
the server decides and then tells the client. And `PartConditionChanged` gets
chatty when you plough through zombies.

**Several players, one car.** Each local player in split screen gets their own
player events, and two players in the same car both get them. If you want an
event once per car, use the world event, or check
`vehicle:getDriver() == player`.

**It costs nothing until someone listens.** A check only runs while at least
one mod listens to one of its events, so the mod sits idle until then. Add and
remove your listeners as usual; the counting happens behind the scenes. A
listener added mid-game starts from that moment.

**One broken check doesn't take down the rest.** If a check throws an error, it
switches itself off, the error prints once, and every other event keeps
working.

### The game's own vehicle events

The game already has a few, and this mod doesn't duplicate them:
`OnSpawnVehicleEnd(vehicle)` when a car appears in the world,
`OnUseVehicle(character, vehicle)` when the "use vehicle" key is pressed, and
`OnPlayerGetDamage(character, "CARCRASHDAMAGE", damage)` when a crash hurts
someone inside.

Prefer `Entered` and `Exited` over the game's `OnEnterVehicle` and
`OnExitVehicle`: those only fire on the client, don't say which seat, and on
exit the car is already gone. And `OnVehicleHorn` exists but the game never
fires it; `HornStarted` does the job.

---

## Your own events

The built-in events cover vanilla cars. For anything else, say a nitro tank
from your own vehicle mod, describe the value to watch and the API turns its
changes into events. Put this in your mod's `shared/` folder:

```lua
require "VehicleEvents"

local function isNitroEmpty(vehicle)
    local nitro = vehicle:getPartById("MyMod_NitroTank")
    if not nitro then return false end
    return nitro:getContainerContentAmount() <= 0
end

VehicleEvents.addWatcher("Nitro", isNitroEmpty, {
    on = "NitroEmpty",      -- fires when it turns true
    off = "NitroRefilled",  -- fires when it turns false
    world = true,           -- the world's view too
})
```

You now have `VehicleEvents_OnPlayerVehicleNitroEmpty`,
`VehicleEvents_OnPlayerVehicleNitroRefilled`, and their two world twins.

To watch something on each part, `addPartWatcher` takes one more function,
choosing the parts:

```lua
local function isSpoiler(part) return part:getId() == "MyMod_Spoiler" end
local function getCondition(part) return part:getCondition() end

VehicleEvents.addPartWatcher("Spoiler", isSpoiler, getCondition, { world = true, slow = true })
```

Without `on` and `off` you get a single event for any change: here,
`...SpoilerChanged`.

| Option | Effect |
|---|---|
| `on`, `off` | Names of the events for "turned true" and "turned false". `off` is optional |
| `world = true` | Also fire the world's view |
| `player = false` | World's view only |
| `slow = true` | Check less often (🐢) |
| `same = function(new, old)` | Say two different values are the same thing, so nothing fires. For items, compare `getID()`: in multiplayer the client gets a fresh copy of an item every time the server syncs it |

Keep the function quick, since it runs often. Return a boolean, a number, a
string or a game object, never a Lua table. Names must be new: reusing one
prints an error and changes nothing.

---

## Settings

The settings are sandbox options, on the **Vehicle Events API** page, so
whoever hosts the game decides: the sandbox screen in single player, the server
settings otherwise. Changes apply at once. The page is translated into every
language the game supports.

| Option | Default | |
|---|---|---|
| Low fuel (%) | 25 | `FuelLow` under this, `FuelNoLongerLow` 5% above it |
| Low battery (%) | 20 | `BatteryLow` under this, `BatteryNoLongerLow` 5% above it |
| Flipped angle (°) | 70 | `Flipped` past this tilt (90 is on its side, 180 on its roof), `BackOnWheels` 25° under it |
| World check interval (ms) | 1000 | Time between two passes over every loaded car |
| World check cars per tick | 50 | Cars checked per tick. Lower is smoother, but a pass takes longer |

From Lua: `VehicleEvents.getSetting("FuelLowPercent")`, with `FuelLowPercent`,
`BatteryLowPercent`, `FlippedAngle`, `WorldCheckMs` or `WorldCarsPerTick`.

---

## How it was tested

Every event here was seen firing in the real game before this was published.

A test mod takes over a fresh world. It parks a police car in the street and
works through it one change at a time: the engine, the lights, the siren, the
radio, the keys, a hotwire, the locks, every door and window, parts and tires,
fuel and battery, the alarm, the trunk's cargo, a trailer with a cow in it, a
second car towing ours, a flip onto the roof, a walk far enough away for the
car to unload, and finally the driver dying at the wheel. It even drives,
pressing real keys. After each change it checks that each promised event fired
once, on the right side, with the right values, and that nothing else did.

The latest runs, on Build 42.21.0:

| | Checks passed | Failed | Lua errors |
|---|---|---|---|
| Single player | 93 | 0 | none |
| Multiplayer, client and dedicated server | 94 | 0 | none |
| Guided, a person driving offroad and back | 10 | 0 | none |

The only thing left untested is split screen, which needs a second controller.
To run the tests yourself, see [TESTING.md](TESTING.md).

---

<sub>`workshop.txt` and `Contents/` are the Workshop upload. Sandbox texts live in
`Translate/<language>/Sandbox.json`, where a percent sign is written `%%`
because the game passes them through `String.format`. The images are drawn by
`tools/make-images.py`. Releases are in [CHANGELOG.md](CHANGELOG.md).</sub>
