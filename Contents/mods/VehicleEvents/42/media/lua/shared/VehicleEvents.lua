-- VehicleEvents: Lua events for vehicle changes the game does in Java without telling Lua
-- (W key engine start, stalls, alarms, doors...). Shared loads before every mod's client
-- and server folder, so the events exist before anyone calls Events.VehicleEvents_*.Add

VehicleEvents = VehicleEvents or {}
local VE = VehicleEvents

VE.PLAYER_PREFIX = "VehicleEvents_OnPlayerVehicle"
VE.WORLD_PREFIX = "VehicleEvents_OnVehicle"

-- settings are sandbox options (media/sandbox-options.txt), read live so an admin change applies at once.
-- the defaults here are used before the sandbox is loaded
VE.DEFAULTS = {
    FuelLowPercent = 25,
    BatteryLowPercent = 20,
    FlippedAngle = 70,
    WorldCheckMs = 1000,
    WorldCarsPerTick = 50,
}

function VE.getSetting(name)
    local vars = SandboxVars and SandboxVars.VehicleEvents
    local value = vars and vars[name]
    if type(value) ~= "number" then return VE.DEFAULTS[name] end
    return value
end

VE.watchers = VE.watchers or {}
VE.watcherList = VE.watcherList or {}
VE.partWatchers = VE.partWatchers or {}
VE.partWatcherList = VE.partWatcherList or {}
VE.partWatcherVersion = (VE.partWatcherVersion or 0) + 1

-- event name -> who made it, so two watchers cant share an event and double fire
VE.eventOwners = VE.eventOwners or {}

------------------------------------------------------------------------
-- listener counting: Lua cant read how many listeners an event has, so our events
-- get an Add / Remove that counts and calls the game's. Checks with no listener are skipped.
-- "or {}" so reloading this file keeps the counts the existing wrappers still use
------------------------------------------------------------------------

VE.listenerCounts = VE.listenerCounts or {}
VE.sideListeners = VE.sideListeners or { player = 0, world = 0 }

local function getSide(eventName)
    if string.sub(eventName, 1, #VE.PLAYER_PREFIX) == VE.PLAYER_PREFIX then
        return "player"
    end
    return "world"
end

-- existedBefore: another mod made this event before us and may have listeners we cant see,
-- so it starts at 1 and is always checked (too high only costs a bit, too low misses events)
local function wrapEvent(eventName, existedBefore)
    local event = Events[eventName]
    if not event or event.vehicleEventsWrapped then return end
    local javaAdd = event.Add
    local javaRemove = event.Remove
    local side = getSide(eventName)
    local counts = {} -- function -> times added
    local base = existedBefore and 1 or 0
    VE.listenerCounts[eventName] = base
    VE.sideListeners[side] = VE.sideListeners[side] + base

    local function addListener(func)
        javaAdd(func)
        if type(func) ~= "function" then return end
        counts[func] = (counts[func] or 0) + 1
        VE.listenerCounts[eventName] = VE.listenerCounts[eventName] + 1
        VE.sideListeners[side] = VE.sideListeners[side] + 1
    end

    local function removeListener(func)
        javaRemove(func)
        local count = counts[func]
        if not count then return end
        if count > 1 then
            counts[func] = count - 1
        else
            counts[func] = nil
        end
        VE.listenerCounts[eventName] = VE.listenerCounts[eventName] - 1
        VE.sideListeners[side] = VE.sideListeners[side] - 1
    end

    event.Add = addListener
    event.Remove = removeListener
    event.vehicleEventsWrapped = true
end

-- fast check for a watcher's events (on / off / changed)
local function hasListeners(events)
    local counts = VE.listenerCounts
    if events.changed then return (counts[events.changed] or 0) > 0 end
    if (counts[events.on] or 0) > 0 then return true end
    return events.off ~= nil and (counts[events.off] or 0) > 0
end

-- any listener in a table of event names (seat events)
function VE.anyListeners(events)
    local counts = VE.listenerCounts
    for _, eventName in pairs(events) do
        if (counts[eventName] or 0) > 0 then return true end
    end
    return false
end

local function registerEvent(eventName, owner)
    local current = VE.eventOwners[eventName]
    if current and current ~= owner then
        print("[VehicleEvents] ERROR: " .. eventName .. " already belongs to " .. current .. ", not added for " .. owner)
        return nil
    end
    VE.eventOwners[eventName] = owner
    local existedBefore = Events[eventName] ~= nil and not Events[eventName].vehicleEventsWrapped
    LuaEventManager.AddEvent(eventName)
    wrapEvent(eventName, existedBefore)
    return eventName
end

-- an event name another watcher already owns
local function isTaken(eventName, owner)
    local current = VE.eventOwners[eventName]
    return current ~= nil and current ~= owner
end

-- all the event names a watcher would make, so they can be checked before anything is added
local function listEventNames(watcher, options)
    local names = {}
    local prefixes = {}
    if options.player ~= false then prefixes[#prefixes + 1] = VE.PLAYER_PREFIX end
    if options.world == true then prefixes[#prefixes + 1] = VE.WORLD_PREFIX end
    for i = 1, #prefixes do
        if options.on then
            names[#names + 1] = prefixes[i] .. options.on
            if options.off then names[#names + 1] = prefixes[i] .. options.off end
        else
            names[#names + 1] = prefixes[i] .. watcher.name .. "Changed"
        end
    end
    return names
end

local function namesAreFree(watcher, options)
    local names = listEventNames(watcher, options)
    for i = 1, #names do
        if isTaken(names[i], watcher.owner) then
            print("[VehicleEvents] ERROR: " .. names[i] .. " already belongs to " .. VE.eventOwners[names[i]]
                .. ", " .. watcher.owner .. " not added")
            return false
        end
    end
    return true
end

local function makeEventNames(prefix, watcher)
    local names = {}
    if watcher.on then
        names.on = registerEvent(prefix .. watcher.on, watcher.owner)
        if watcher.off then
            names.off = registerEvent(prefix .. watcher.off, watcher.owner)
        end
    else
        names.changed = registerEvent(prefix .. watcher.name .. "Changed", watcher.owner)
    end
    return names
end

-- which event a change fires, nil if there is none
function VE.getEventName(events, value)
    if not events then return nil end
    if events.changed then return events.changed end
    if value then return events.on end
    return events.off
end

-- on / off watchers only care about true vs false, so nil -> false is not a change.
-- two different objects (towing car A then car B) still count as a change
local function isChange(events, value, old)
    if events.changed then return value ~= old end
    if value then return value ~= old end
    return old ~= nil and old ~= false
end

local function setupWatcher(watcher, getter, options)
    watcher.get = getter
    watcher.on = options.on
    watcher.off = options.off
    watcher.world = options.world == true
    watcher.slow = options.slow == true
    watcher.failed = false
    watcher.playerEvents = nil
    if options.player ~= false then
        watcher.playerEvents = makeEventNames(VE.PLAYER_PREFIX, watcher)
    end
    watcher.worldEvents = nil
    if watcher.world then
        watcher.worldEvents = makeEventNames(VE.WORLD_PREFIX, watcher)
    end
end

-- true while this file adds the built in watchers, so other mods cant replace them
local loadingBuiltIns = false

local function canSetup(watcher, name)
    if watcher.builtIn and not loadingBuiltIns then
        print("[VehicleEvents] ERROR: watcher " .. name .. " is built in, pick another name")
        return false
    end
    return true
end

-- name: unique id, getter(vehicle, oldValue): value compared with ==
-- options.on / options.off: fire <on> when the value turns truthy, <off> when it turns falsy (off is optional)
--   without them it fires <name>Changed
-- options.world: also fire the world events (every loaded car, SP and server)
-- options.player = false: no player events (world only)
-- options.slow: only check about once a second (player) or every few scans (world)
function VE.addWatcher(name, getter, options)
    options = options or {}
    local watcher = VE.watchers[name]
    if watcher and not canSetup(watcher, name) then
        return nil
    end
    local isNew = watcher == nil
    if isNew then
        watcher = { name = name, owner = "watcher " .. name }
    end
    if not namesAreFree(watcher, options) then
        return nil
    end
    if isNew then
        VE.watchers[name] = watcher
        table.insert(VE.watcherList, watcher)
    end
    watcher.builtIn = loadingBuiltIns
    setupWatcher(watcher, getter, options)
    return watcher
end

-- same as addWatcher but for each part where filter(part) is true
-- getter(part, oldValue), events get the part: player (player, part, new, old), world (vehicle, part, new, old)
function VE.addPartWatcher(name, filter, getter, options)
    options = options or {}
    local watcher = VE.partWatchers[name]
    if watcher and not canSetup(watcher, name) then
        return nil
    end
    local isNew = watcher == nil
    if isNew then
        watcher = { name = name, owner = "part watcher " .. name }
    end
    if not namesAreFree(watcher, options) then
        return nil
    end
    if isNew then
        VE.partWatchers[name] = watcher
        table.insert(VE.partWatcherList, watcher)
    end
    watcher.builtIn = loadingBuiltIns
    watcher.filter = filter
    setupWatcher(watcher, getter, options)
    VE.partWatcherVersion = VE.partWatcherVersion + 1
    return watcher
end

-- built in events that are not watchers
local function registerBuiltIn(prefix, list)
    local names = {}
    for key, suffix in pairs(list) do
        names[key] = registerEvent(prefix .. suffix, "built in")
    end
    return names
end

VE.seatEvents = {
    player = registerBuiltIn(VE.PLAYER_PREFIX, { entered = "Entered", exited = "Exited", seatChanged = "SeatChanged" }),
    world = registerBuiltIn(VE.WORLD_PREFIX, { entered = "Entered", exited = "Exited", seatChanged = "SeatChanged" }),
}
-- no Loaded: vanilla OnSpawnVehicleEnd already fires when a car is added to the world, instantly, on both sides
VE.loadEvents = registerBuiltIn(VE.WORLD_PREFIX, { unloaded = "Unloaded" })

------------------------------------------------------------------------
-- shared update helpers, used by the client poller and the server scan
------------------------------------------------------------------------

-- state: one table per car per side { watch = {}, parts = {}, ... }
function VE.newState()
    return { watch = {}, parts = {} }
end

-- value of a check that was skipped (no listener), so turning it back on records instead of firing
-- kept on VE so reloading this file keeps the same marker the stored states use
VE.UNKNOWN = VE.UNKNOWN or {}
local UNKNOWN = VE.UNKNOWN

-- a getter or filter from another mod can throw, that must not stop the other checks.
-- the game logs every Java error even inside pcall, so a watcher that fails is switched off
-- (until its file is reloaded) instead of failing again every tick
local function safeCall(watcher, func, target, old)
    local ok, result = pcall(func, target, old)
    if ok then return true, result end
    watcher.failed = true
    print("[VehicleEvents] ERROR in watcher " .. watcher.name .. ", switched off: " .. tostring(result))
    return false, nil
end

-- player: nil for world events. doFire false = just record (first sight)
-- triggerEvent takes at most 4 arguments, every event here stays at 4
function VE.updateWatchers(state, vehicle, player, doFire, includeSlow)
    local values = state.watch
    local list = VE.watcherList
    for i = 1, #list do
        local watcher = list[i]
        local events = player and watcher.playerEvents or watcher.worldEvents
        if events and not watcher.failed and (includeSlow or not watcher.slow) then
            if hasListeners(events) then
                local old = values[watcher.name]
                local known = old ~= UNKNOWN
                if not known then old = nil end
                local ok, value = safeCall(watcher, watcher.get, vehicle, old)
                if ok then
                    if doFire and known and isChange(events, value, old) then
                        local eventName = VE.getEventName(events, value)
                        if eventName and player then
                            triggerEvent(eventName, player, vehicle, value, old)
                        elseif eventName then
                            triggerEvent(eventName, vehicle, value, old)
                        end
                    end
                    values[watcher.name] = value
                end
            else
                values[watcher.name] = UNKNOWN
            end
        end
    end
end

-- parts dont change unless the car script does, so the list is built once per car.
-- values start UNKNOWN so nothing is read until someone listens
local function buildParts(state, vehicle)
    local entries = state.parts
    for i = #entries, 1, -1 do
        entries[i] = nil
    end
    local list = VE.partWatcherList
    for p = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(p)
        for i = 1, #list do
            local watcher = list[i]
            local ok, matches = false, false
            if not watcher.failed then
                ok, matches = safeCall(watcher, watcher.filter, part, nil)
            end
            if ok and matches then
                entries[#entries + 1] = { part = part, watcher = watcher, value = UNKNOWN }
            end
        end
    end
    state.partsVehicle = vehicle
    state.partsScript = vehicle:getScriptName()
    state.partsCount = vehicle:getPartCount()
    state.partsVersion = VE.partWatcherVersion
end

function VE.updateParts(state, vehicle, player, doFire, includeSlow)
    if #VE.partWatcherList == 0 then return end
    if vehicle ~= state.partsVehicle or state.partsVersion ~= VE.partWatcherVersion
        or state.partsCount ~= vehicle:getPartCount() or state.partsScript ~= vehicle:getScriptName() then
        -- other car, new script or new watchers: rebuild, values get recorded on the next check
        buildParts(state, vehicle)
    end
    local entries = state.parts
    for i = 1, #entries do
        local entry = entries[i]
        local watcher = entry.watcher
        local events = player and watcher.playerEvents or watcher.worldEvents
        if events and not watcher.failed and (includeSlow or not watcher.slow) then
            if hasListeners(events) then
                local old = entry.value
                local known = old ~= UNKNOWN
                if not known then old = nil end
                local ok, value = safeCall(watcher, watcher.get, entry.part, old)
                if ok then
                    if doFire and known and isChange(events, value, old) then
                        local eventName = VE.getEventName(events, value)
                        -- player part events skip the vehicle (part:getVehicle()) to stay at 4 arguments
                        if eventName and player then
                            triggerEvent(eventName, player, entry.part, value, old)
                        elseif eventName then
                            triggerEvent(eventName, vehicle, entry.part, value, old)
                        end
                    end
                    entry.value = value
                end
            else
                entry.value = UNKNOWN
            end
        end
    end
end

------------------------------------------------------------------------
-- built in watchers
------------------------------------------------------------------------

local function getEngineRunning(v) return v:isEngineRunning() end
local function getEngineState(v) return v:getEngineState() end
local function getGear(v) return v:getTransmissionNumber() end
local function getHeadlights(v) return v:getHeadlightsOn() end
-- isAlarmSounding needs a listener nearby (always false on a server), isAlarmActive is the real state
local function getAlarmSounding(v) return v:isAlarmActive() end
local function getAlarmArmed(v) return v:isAlarmed() end
local function getSiren(v) return v:isSirening() end
local function getKeysInIgnition(v) return v:isKeysInIgnition() end
local function getHotwired(v) return v:isHotwired() end
local function getHotwireBroken(v) return v:isHotwiredBroken() end
local function getTowing(v) return v:getVehicleTowing() end
local function getTowedBy(v) return v:getVehicleTowedBy() end
local function getAnyDoorLocked(v) return v:isAnyDoorLocked() end
local function getTrunkLocked(v) return v:isTrunkLocked() end
local function getHasFuel(v) return v:hasEnoughGasToRun() end
local function getLiveBattery(v) return v:hasLiveBattery() end
local function getDriveable(v) return v:isDriveable() end
local function getTireMissing(v) return v:isAnyTireMissing() end
local function getCruiseControl(v) return v:isRegulator() end
local function getHorn(v) return v:isHornSounding() end
local function getOffroad(v) return v:isDoingOffroad() end

local function getRadioOn(v)
    local radio = v:getPartById("Radio")
    if not radio then return false end
    local device = radio:getDeviceData()
    if not device then return false end
    return device:getIsTurnedOn()
end

local function getHasPassenger(v) return v:hasPassenger() end
local function getReversing(v) return v:getTransmissionNumber() == -1 end
local function getLightbar(v) return v:getLightbarLightsMode() > 0 end
local function getAnimals(v) return v:getCurrentTotalAnimalSize() end
local function getCargo(v) return v:getTotalContainerItemWeight() end

-- the game sets this the first time a player opens one of the car's doors (ISOpenVehicleDoor),
-- and clears it again when the alarm gets armed
local function getPreviouslyOpened(v) return v:isPreviouslyEntered() end

local function getHeaterOn(v)
    local heater = v:getPartById("Heater")
    if not heater then return false end
    return heater:getModData().active == true
end

-- the low / ok checks below use two thresholds so a value sitting on the line doesnt spam.
-- getUpVectorDot is the cosine of the tilt: 1 upright, 0 on its side, -1 on its roof
local function getFlipped(v, wasFlipped)
    local angle = VE.getSetting("FlippedAngle")
    if wasFlipped then angle = math.max(5, angle - 25) end
    return v:getUpVectorDot() < math.cos(math.rad(angle))
end

-- no tank keeps the last state (nil on first sight, which is not a change)
local function getFuelLow(v, wasLow)
    if not v:getPartById("GasTank") then return wasLow end
    local percent = v:getRemainingFuelPercentage()
    local low = VE.getSetting("FuelLowPercent")
    if wasLow then return percent < low + 5 end
    return percent < low
end

-- no battery keeps the last state, PowerLost already covers that
local function getBatteryLow(v, wasLow)
    local battery = v:getPartById("Battery")
    if not battery or not battery:getInventoryItem() then return wasLow end
    local percent = v:getBatteryCharge() * 100
    local low = VE.getSetting("BatteryLowPercent")
    if wasLow then return percent < low + 5 end
    return percent < low
end

-- two thresholds so a car crawling around one speed doesnt spam start/stop
local function getMoving(v, wasMoving)
    local speed = v:getCurrentAbsoluteSpeedKmHour()
    if wasMoving then return speed > 0.5 end
    return speed > 2
end

loadingBuiltIns = true

VE.addWatcher("Engine", getEngineRunning, { on = "EngineStarted", off = "EngineStopped", world = true })
VE.addWatcher("EngineState", getEngineState, { world = true })
VE.addWatcher("Moving", getMoving, { on = "StartedMoving", off = "StoppedMoving", world = true })
VE.addWatcher("Gear", getGear)
VE.addWatcher("Headlights", getHeadlights, { on = "HeadlightsTurnedOn", off = "HeadlightsTurnedOff", world = true })
VE.addWatcher("Alarm", getAlarmSounding, { on = "AlarmStartedRinging", off = "AlarmStoppedRinging", world = true })
VE.addWatcher("AlarmArmed", getAlarmArmed, { on = "AlarmArmed", off = "AlarmDisarmed", world = true })
VE.addWatcher("Siren", getSiren, { on = "SirenTurnedOn", off = "SirenTurnedOff", world = true })
VE.addWatcher("Radio", getRadioOn, { on = "RadioTurnedOn", off = "RadioTurnedOff", world = true })
VE.addWatcher("Horn", getHorn, { on = "HornStarted", off = "HornStopped" })
VE.addWatcher("CruiseControl", getCruiseControl, { on = "CruiseControlTurnedOn", off = "CruiseControlTurnedOff" })
VE.addWatcher("Keys", getKeysInIgnition, { on = "IgnitionKeyInserted", off = "IgnitionKeyRemoved" })
VE.addWatcher("Hotwire", getHotwired, { on = "Hotwired", off = "HotwireRemoved", world = true })
VE.addWatcher("HotwireBroken", getHotwireBroken, { on = "HotwireBroken", off = "HotwireRepaired", world = true })
VE.addWatcher("DoorLocks", getAnyDoorLocked, { on = "AnyDoorLocked", off = "AllDoorsUnlocked", world = true })
VE.addWatcher("TrunkLock", getTrunkLocked, { on = "TrunkLocked", off = "TrunkUnlocked", world = true })
VE.addWatcher("Fuel", getHasFuel, { on = "FuelRefilled", off = "FuelEmpty", world = true })
VE.addWatcher("Battery", getLiveBattery, { on = "PowerRestored", off = "PowerLost", world = true })
VE.addWatcher("Driveable", getDriveable, { on = "BecameDriveable", off = "BrokeDown", world = true, slow = true })
VE.addWatcher("Tires", getTireMissing, { on = "TireMissing", off = "AllTiresInstalled", world = true, slow = true })
VE.addWatcher("Offroad", getOffroad, { on = "WentOffroad", off = "BackOnRoad", slow = true })
VE.addWatcher("FuelLow", getFuelLow, { on = "FuelLow", off = "FuelNoLongerLow", world = true })
VE.addWatcher("BatteryLow", getBatteryLow, { on = "BatteryLow", off = "BatteryNoLongerLow", world = true })
VE.addWatcher("Flipped", getFlipped, { on = "Flipped", off = "BackOnWheels", world = true })
VE.addWatcher("Reversing", getReversing, { on = "ShiftedIntoReverse", off = "ShiftedOutOfReverse" })
VE.addWatcher("Lightbar", getLightbar, { on = "LightbarTurnedOn", off = "LightbarTurnedOff", world = true })
VE.addWatcher("Heater", getHeaterOn, { on = "HeaterTurnedOn", off = "HeaterTurnedOff", world = true })
VE.addWatcher("Occupied", getHasPassenger, { on = "BecameOccupied", off = "BecameEmpty", world = true, player = false })
VE.addWatcher("FirstOpened", getPreviouslyOpened, { on = "FirstOpened", world = true, player = false })
VE.addWatcher("Animals", getAnimals, { world = true })
VE.addWatcher("Cargo", getCargo, { world = true, slow = true })
VE.addWatcher("Towing", getTowing, { on = "StartedTowing", off = "StoppedTowing", world = true })
VE.addWatcher("BeingTowed", getTowedBy, { on = "StartedBeingTowed", off = "StoppedBeingTowed", world = true })

------------------------------------------------------------------------
-- built in part watchers
------------------------------------------------------------------------

local function hasDoor(part) return part:getDoor() ~= nil end
local function hasWindow(part) return part:getWindow() ~= nil end
local function isInstallable(part)
    local types = part:getItemType()
    return types ~= nil and not types:isEmpty()
end

local function isTire(part) return part:getWheelIndex() ~= -1 end

-- a removed tire keeps its last state, PartRemoved already covers that
local function getTireFlat(part, wasFlat)
    if not part:getInventoryItem() then return wasFlat end
    return part:getContainerContentAmount() <= 0
end

local function getDoorOpen(part) return part:getDoor():isOpen() end
local function getDoorLocked(part) return part:getDoor():isLocked() end
local function getWindowSmashed(part) return part:getWindow():isDestroyed() end
local function getWindowOpen(part) return part:getWindow():isOpen() end
local function getInstalledItem(part) return part:getInventoryItem() end
local function getCondition(part) return part:getCondition() end

VE.addPartWatcher("Door", hasDoor, getDoorOpen, { on = "DoorOpened", off = "DoorClosed", world = true })
VE.addPartWatcher("DoorLock", hasDoor, getDoorLocked, { on = "DoorLocked", off = "DoorUnlocked", world = true })
VE.addPartWatcher("Window", hasWindow, getWindowSmashed, { on = "WindowSmashed", off = "WindowRepaired", world = true })
VE.addPartWatcher("WindowOpen", hasWindow, getWindowOpen, { on = "WindowOpened", off = "WindowClosed", world = true })
VE.addPartWatcher("TireFlat", isTire, getTireFlat, { on = "TireWentFlat", off = "TireInflated", world = true, slow = true })
VE.addPartWatcher("Part", isInstallable, getInstalledItem, { on = "PartInstalled", off = "PartRemoved", world = true, slow = true })
VE.addPartWatcher("PartCondition", isInstallable, getCondition, { world = true, slow = true })

loadingBuiltIns = false
