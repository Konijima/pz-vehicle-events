# Vehicle Events API

> **Lua events for everything cars do.** A Project Zomboid (Build 42) mod for
> modders. Mod ID `VehicleEvents`.

The game does a lot of car things without telling Lua. Pressing W starts the
engine, an engine stalls, an alarm goes off, a door opens: no event fires.
This mod watches cars and fires an event when something changes.

**Contents**

1. [Quick start](#quick-start)
2. [Client or server?](#client-or-server)
3. [Parameters](#parameters)
4. [Event list](#event-list)
5. [Good to know](#good-to-know)
6. [Vanilla events you can still use](#vanilla-events-you-can-still-use)
7. [Make your own events](#make-your-own-events)
8. [Settings](#settings)

---

## Quick start

Add this mod as a requirement of your mod, then listen like any game event:

```lua
-- media/lua/client/MyMod.lua
local function onEngineStarted(player, vehicle)
    print("engine started")
end

Events.VehicleEvents_OnPlayerVehicleEngineStarted.Add(onEngineStarted)
```

No `require` needed in `client/` or `server/` files.

Start the game with `-debug` to see every event printed in the console.

---

## Client or server?

Every event comes in two kinds. Pick the one that matches where your code runs.

| | 🧍 Player event | 🌍 World event |
|---|---|---|
| **Name starts with** | `VehicleEvents_OnPlayerVehicle...` | `VehicleEvents_OnVehicle...` |
| **Runs on** | Client (your game) | Server |
| **Watches** | The car you sit in (any seat) | Every loaded car, even empty |
| **Speed** | Every tick (🐢 events: every second) | Every second (🐢 events: every 5 seconds), see [settings](#settings) |
| **Your code goes in** | `media/lua/client/` | `media/lua/server/` |

Where each kind fires:

| | 🧍 Player events | 🌍 World events |
|---|---|---|
| Single player | ✅ | ✅ |
| Multiplayer client (co-op included) | ✅ | — |
| Multiplayer server | — | ✅ |

> In single player your game is both client and server, so a car you drive
> fires each change twice: once per kind.

---

## Parameters

Each event below shows its parameters, for the 🧍 player version and the 🌍
world version. **—** means that version does not exist.

- On / off events (like `EngineStarted` / `EngineStopped`) also get the new and
  old value after the listed ones (`true` / `false`). You never need them.
- Player part events skip the vehicle (the game allows only 4 parameters). Use
  `part:getVehicle()`.
- `part:getId()` tells you which part: `DoorFrontLeft`, `TrunkDoor`,
  `EngineDoor`...
- Seat `0` is the driver. The other numbers follow the car's script.

```lua
-- a player event: listed params are (player, vehicle)
local function onHeadlightsOn(player, vehicle)
end
Events.VehicleEvents_OnPlayerVehicleHeadlightsTurnedOn.Add(onHeadlightsOn)

-- the world version of the same event: listed params are (vehicle)
local function onAnyHeadlightsOn(vehicle)
end
Events.VehicleEvents_OnVehicleHeadlightsTurnedOn.Add(onAnyHeadlightsOn)
```

---

## Event list

Put `VehicleEvents_OnPlayerVehicle` or `VehicleEvents_OnVehicle` in front of a
name. Example: `EngineStarted` → `VehicleEvents_OnPlayerVehicleEngineStarted`.

Events marked 🐢 are checked less often (every second for players, every 5th
world check for the world), so they can be a little late.

### 🚪 Getting in and out

| Events | Fires when | 🧍 Player params | 🌍 World params |
|---|---|---|---|
| `Entered` | Someone gets in | `player, vehicle, seat` | `vehicle, character, seat` |
| `Exited` | Someone gets out (dying in the car counts) | `player, vehicle, seat` | `vehicle, character, seat` |
| `SeatChanged` | Someone moves to another seat | `player, vehicle, newSeat, oldSeat` | `vehicle, character, newSeat, oldSeat` |
| `BecameOccupied` / `BecameEmpty` | First person gets in / last person gets out | — | `vehicle` |
| `FirstOpened` | A player opens one of the car's doors for the first time | — | `vehicle` |

> Player events only watch the car you sit in, so they can't see the moment a
> car becomes occupied, empty or first opened. Those happen before you are in
> or after you left.

### 🔧 Engine and power

| Events | Fires when | 🧍 Player params | 🌍 World params |
|---|---|---|---|
| `EngineStarted` / `EngineStopped` | The engine is running / stops (turned off, stalled, no fuel) | `player, vehicle` | `vehicle` |
| `EngineStateChanged` | The engine state changes (see below) | `player, vehicle, newState, oldState` | `vehicle, newState, oldState` |
| `FuelEmpty` / `FuelRefilled` | The tank runs dry / has fuel again | `player, vehicle` | `vehicle` |
| `FuelLow` / `FuelNoLongerLow` | Fuel goes below 25% / back above 30% ([settings](#settings)) | `player, vehicle` | `vehicle` |
| `PowerLost` / `PowerRestored` | The car has no power (battery dead or removed) / has power again | `player, vehicle` | `vehicle` |
| `BatteryLow` / `BatteryNoLongerLow` | Charge goes below 20% / back above 25% ([settings](#settings)) | `player, vehicle` | `vehicle` |
| `BrokeDown` / `BecameDriveable` 🐢 | The car can't drive anymore / can again | `player, vehicle` | `vehicle` |

Engine states (`newState`, `oldState`): `Idle`, `Starting`, `RetryingStarting`,
`StartingSuccess`, `StartingFailed`, `Running`, `Stalling`, `ShuttingDown`.
Compare with `tostring(newState) == "Running"`. A failed start only shows up
here, because `EngineStarted` waits until the engine really runs.

### 🏎️ Driving

| Events | Fires when | 🧍 Player params | 🌍 World params |
|---|---|---|---|
| `StartedMoving` / `StoppedMoving` | Speed goes above 2 km/h / below 0.5 km/h | `player, vehicle` | `vehicle` |
| `Flipped` / `BackOnWheels` | The car ends up on its roof or side / back on its wheels ([settings](#settings)) | `player, vehicle` | `vehicle` |
| `GearChanged` | The gear changes (`-1` = R, `0` = N, `1` and up) | `player, vehicle, newGear, oldGear` | — |
| `ShiftedIntoReverse` / `ShiftedOutOfReverse` | The gear goes into / out of R (moving or not) | `player, vehicle` | — |
| `CruiseControlTurnedOn` / `CruiseControlTurnedOff` | Cruise control turns on / off (driver only, see below) | `player, vehicle` | — |
| `WentOffroad` / `BackOnRoad` 🐢 | The car leaves / gets back on the road | `player, vehicle` | — |

### 💡 Lights and sounds

| Events | Fires when | 🧍 Player params | 🌍 World params |
|---|---|---|---|
| `HeadlightsTurnedOn` / `HeadlightsTurnedOff` | Headlights on / off | `player, vehicle` | `vehicle` |
| `LightbarTurnedOn` / `LightbarTurnedOff` | Police lights on / off (siren or not) | `player, vehicle` | `vehicle` |
| `SirenTurnedOn` / `SirenTurnedOff` | Siren on / off | `player, vehicle` | `vehicle` |
| `RadioTurnedOn` / `RadioTurnedOff` | Car radio on / off | `player, vehicle` | `vehicle` |
| `HeaterTurnedOn` / `HeaterTurnedOff` | Heater or AC on / off | `player, vehicle` | `vehicle` |
| `HornStarted` / `HornStopped` | Horn starts / stops | `player, vehicle` | — |

### 🔐 Alarm, keys and locks

| Events | Fires when | 🧍 Player params | 🌍 World params |
|---|---|---|---|
| `AlarmStartedRinging` / `AlarmStoppedRinging` | The alarm starts / stops sounding | `player, vehicle` | `vehicle` |
| `AlarmArmed` / `AlarmDisarmed` | The alarm gets armed / disarmed (also when it goes off) | `player, vehicle` | `vehicle` |
| `IgnitionKeyInserted` / `IgnitionKeyRemoved` | Keys go in / come out of the ignition | `player, vehicle` | — |
| `Hotwired` / `HotwireRemoved` | The car gets hotwired / no longer is | `player, vehicle` | `vehicle` |
| `HotwireBroken` / `HotwireRepaired` | The hotwire breaks / works again | `player, vehicle` | `vehicle` |
| `AnyDoorLocked` / `AllDoorsUnlocked` | One seat door gets locked / no seat door is locked anymore (trunk not included) | `player, vehicle` | `vehicle` |
| `TrunkLocked` / `TrunkUnlocked` | The trunk gets locked / unlocked | `player, vehicle` | `vehicle` |

### 🪟 Doors and windows

| Events | Fires when | 🧍 Player params | 🌍 World params |
|---|---|---|---|
| `DoorOpened` / `DoorClosed` | A door, the trunk or the hood opens / closes | `player, part` | `vehicle, part` |
| `DoorLocked` / `DoorUnlocked` | One door gets locked / unlocked | `player, part` | `vehicle, part` |
| `WindowOpened` / `WindowClosed` | A window rolls down / up | `player, part` | `vehicle, part` |
| `WindowSmashed` / `WindowRepaired` | A window breaks / is fixed | `player, part` | `vehicle, part` |

### 🛞 Parts and tires

| Events | Fires when | 🧍 Player params | 🌍 World params |
|---|---|---|---|
| `PartInstalled` / `PartRemoved` 🐢 | A part is put in / taken out | `player, part, newItem, oldItem` | `vehicle, part, newItem, oldItem` |
| `PartConditionChanged` 🐢 | A part's condition changes (0 to 100) | `player, part, newCondition, oldCondition` | `vehicle, part, newCondition, oldCondition` |
| `TireWentFlat` / `TireInflated` 🐢 | A tire has no air left / gets air again | `player, part` | `vehicle, part` |
| `TireMissing` / `AllTiresInstalled` 🐢 | A tire is missing / all tires are back | `player, vehicle` | `vehicle` |

For `PartInstalled`, `newItem` is the item put in. For `PartRemoved`, `oldItem`
is the item taken out (`newItem` is `nil`).

### 📦 Cargo and towing

| Events | Fires when | 🧍 Player params | 🌍 World params |
|---|---|---|---|
| `CargoChanged` 🐢 | Items go in or out | `player, vehicle, newWeight, oldWeight` | `vehicle, newWeight, oldWeight` |
| `AnimalsChanged` | Animals go in or out of a trailer | `player, vehicle, newSize, oldSize` | `vehicle, newSize, oldSize` |
| `StartedTowing` / `StoppedTowing` | The car starts / stops towing another | `player, vehicle, newTowed, oldTowed` | `vehicle, newTowed, oldTowed` |
| `StartedBeingTowed` / `StoppedBeingTowed` | The car gets towed / is let go | `player, vehicle, newTower, oldTower` | `vehicle, newTower, oldTower` |

For `StartedTowing`, `newTowed` is the car being towed. For `StoppedTowing`,
`oldTowed` is the car that was towed (`newTowed` is `nil`). Same idea for
`newTower` / `oldTower`: the car doing the towing.

### 🌍 World only

| Events | Fires when | 🧍 Player params | 🌍 World params |
|---|---|---|---|
| `Unloaded` | A car is unloaded or deleted. It is already out of the world | — | `vehicle` |

---

## Good to know

**⏱️ Timing**

- Getting in a car only fires `Entered`. The rest waits for a change after
  that: getting into a running car does not fire `EngineStarted`.
- Loading a save while sitting in a car fires `Entered`.
- A car loading in fires nothing.
- World events can miss a change that lasts less than one check.
- In multiplayer, player events arrive a little late: the server decides, then
  tells the client.
- Split screen works: each local player gets their own player events. Two
  players in the same car both get them (once each). Use the world event, or
  check `vehicle:getDriver() == player`, if you want it once per car.

**🎯 Odd cases**

- `AlarmDisarmed` also fires when the alarm goes off: the game clears the armed
  flag when it triggers.
- `FirstOpened` is the game's "previously entered" flag. It is set the first
  time a player opens a door, and cleared when the alarm gets armed, so it can
  fire again after that.
- Swapping a part, or switching towed cars, between two checks fires
  `PartInstalled` / `StartedTowing` again, without the "removed" event first.
- `PartConditionChanged` fires a lot while you hit zombies.
- Cruise control events only fire in the driver's game: the game does not send
  cruise control on / off to the other players.

**⚡ Performance**

- Checks only run while some mod listens to their event. Nobody listening =
  almost no cost. You use `Events.X.Add` / `Events.X.Remove` as usual, the
  counting happens in the background.
- A listener added mid-game starts from that moment: its first check only
  records, changes are caught from the next one.
- If a watcher's function errors, that watcher is switched off (until its
  file is reloaded) and the other checks keep running. The game prints the
  error once, not every tick.

---

## Vanilla events you can still use

The game already has these. This mod does not copy them.

| Vanilla event | Use it for |
|---|---|
| `OnSpawnVehicleEnd(vehicle)` | A car is added to the world (spawned or loaded). Instant, client and server |
| `OnUseVehicle(character, vehicle)` | The "use vehicle" key is pressed |
| `OnPlayerGetDamage(character, "CARCRASHDAMAGE", damage)` | Someone inside gets hurt in a crash |

Why use this mod's `Entered` / `Exited` instead of the game's `OnEnterVehicle`
/ `OnExitVehicle`? Those only fire on the client, give no seat, and on exit the
vehicle is already gone.

`OnVehicleHorn` exists in the game but nothing ever fires it. Use
`HornStarted` / `HornStopped`.

---

## Make your own events

The built-in events cover vanilla cars. Use this for things the game does not
have, like a part from a modded vehicle. Put it in your mod's `shared/` folder.

### A car value: `addWatcher`

```lua
require "VehicleEvents"

-- return true when the nitro tank is empty
local function isNitroEmpty(vehicle)
    local nitro = vehicle:getPartById("MyMod_NitroTank")
    if not nitro then
        return false -- this car has no nitro tank
    end
    return nitro:getContainerContentAmount() <= 0
end

VehicleEvents.addWatcher("Nitro", isNitroEmpty, {
    on = "NitroEmpty",     -- fires when isNitroEmpty goes from false to true
    off = "NitroRefilled", -- fires when isNitroEmpty goes from true to false
    world = true,          -- also make the world events
})
```

You get `VehicleEvents_OnPlayerVehicleNitroEmpty`,
`VehicleEvents_OnPlayerVehicleNitroRefilled`, and the same two world events.

### A value on each part: `addPartWatcher`

One more function picks which parts to watch:

```lua
-- which parts to watch: only my mod's spoilers
local function isSpoiler(part)
    return part:getId() == "MyMod_Spoiler"
end

-- the value to watch: the spoiler's condition
local function getCondition(part)
    return part:getCondition()
end

VehicleEvents.addPartWatcher("Spoiler", isSpoiler, getCondition, {
    world = true,
    slow = true, -- no need to check every tick
})
```

No `on` / `off` here, so you get one event: `...SpoilerChanged`.

### Options

| Option | What it does |
|---|---|
| `on` / `off` | Event names for when the value turns true / false. `off` is optional |
| *(no `on`)* | One `<name>Changed` event for any change |
| `world = true` | Also make world events (server) |
| `player = false` | No player events, world only |
| `slow = true` | Check less often |

Rules:

- Keep the function fast: it runs very often.
- Return a true/false, number, string or game object. Not a Lua table.
- Names must be new. A built-in watcher name or a taken event name prints an
  error in the console, and nothing changes.

---

## Settings

Settings are **sandbox options**, on the **Vehicle Events API** page. Whoever
hosts the game sets them: the sandbox screen in single player, the server
settings for co-op and dedicated servers. The mod reads them live, so a change
applies at once.

| Option | Default | What it does |
|---|---|---|
| Low fuel (%) | `25` | `FuelLow` below this. `FuelNoLongerLow` once 5% above again |
| Low battery (%) | `20` | `BatteryLow` below this. `BatteryNoLongerLow` once 5% above again |
| Flipped angle (degrees) | `70` | `Flipped` when tilted more than this from upright (90 = on its side, 180 = on its roof). `BackOnWheels` once back under this minus 25 |
| World check interval (ms) | `1000` | Time between two checks of every loaded car |
| World check cars per tick | `50` | Cars handled per tick. Lower = smoother, but a full check takes longer |

From Lua: `VehicleEvents.getSetting("FuelLowPercent")`. The names are
`FuelLowPercent`, `BatteryLowPercent`, `FlippedAngle`, `WorldCheckMs` and
`WorldCarsPerTick`.

---

## Files

`workshop.txt` and `Contents/` are the Workshop upload folder. `preview.png` is
still missing. See [CHANGELOG.md](CHANGELOG.md) for releases.
