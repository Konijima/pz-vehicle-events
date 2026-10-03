-- VehicleEventsTest: automatic in-game test of every Vehicle Events API event. Not for the Workshop.
-- shared part: the event list from the README, the recorder, the log and the test steps.
-- the client file runs the steps (SP, MP client), the server file does the car side in MP
require "VehicleEvents"

VET = VET or {}
local VE = VehicleEvents

VET.SIDE = isServer() and "server" or (isClient() and "client" or "sp")
VET.MP = isServer() or isClient()

------------------------------------------------------------------------
-- every event in the README. p = player version, w = world version
------------------------------------------------------------------------

VET.EVENTS = {
    Entered = "pw", Exited = "pw", SeatChanged = "pw",
    BecameOccupied = "w", BecameEmpty = "w", FirstOpened = "w",
    EngineStarted = "pw", EngineStopped = "pw", EngineStateChanged = "pw",
    FuelEmpty = "pw", FuelRefilled = "pw", FuelLow = "pw", FuelNoLongerLow = "pw",
    PowerLost = "pw", PowerRestored = "pw", BatteryLow = "pw", BatteryNoLongerLow = "pw",
    BrokeDown = "pw", BecameDriveable = "pw",
    StartedMoving = "pw", StoppedMoving = "pw", Flipped = "pw", BackOnWheels = "pw",
    GearChanged = "p", ShiftedIntoReverse = "p", ShiftedOutOfReverse = "p",
    CruiseControlTurnedOn = "p", CruiseControlTurnedOff = "p", WentOffroad = "p", BackOnRoad = "p",
    HeadlightsTurnedOn = "pw", HeadlightsTurnedOff = "pw", LightbarTurnedOn = "pw", LightbarTurnedOff = "pw",
    SirenTurnedOn = "pw", SirenTurnedOff = "pw", RadioTurnedOn = "pw", RadioTurnedOff = "pw",
    HeaterTurnedOn = "pw", HeaterTurnedOff = "pw", HornStarted = "p", HornStopped = "p",
    AlarmStartedRinging = "pw", AlarmStoppedRinging = "pw", AlarmArmed = "pw", AlarmDisarmed = "pw",
    IgnitionKeyInserted = "p", IgnitionKeyRemoved = "p", Hotwired = "pw", HotwireRemoved = "pw",
    HotwireBroken = "pw", HotwireRepaired = "pw", AnyDoorLocked = "pw", AllDoorsUnlocked = "pw",
    TrunkLocked = "pw", TrunkUnlocked = "pw",
    DoorOpened = "pw", DoorClosed = "pw", DoorLocked = "pw", DoorUnlocked = "pw",
    WindowOpened = "pw", WindowClosed = "pw", WindowSmashed = "pw", WindowRepaired = "pw",
    PartInstalled = "pw", PartRemoved = "pw", PartConditionChanged = "pw",
    TireWentFlat = "pw", TireInflated = "pw", TireMissing = "pw", AllTiresInstalled = "pw",
    CargoChanged = "pw", AnimalsChanged = "w", StartedTowing = "pw", StoppedTowing = "pw",
    StartedBeingTowed = "pw", StoppedBeingTowed = "pw",
    Unloaded = "w",
}

-- events whose second argument is a part instead of the car
VET.PART_EVENTS = {
    DoorOpened = true, DoorClosed = true, DoorLocked = true, DoorUnlocked = true,
    WindowOpened = true, WindowClosed = true, WindowSmashed = true, WindowRepaired = true,
    PartInstalled = true, PartRemoved = true, PartConditionChanged = true,
    TireWentFlat = true, TireInflated = true,
}

-- world seat events: (vehicle, character, seat...)
VET.SEAT_EVENTS = { Entered = true, Exited = true, SeatChanged = true }

-- no setter exists for these, a person has to drive (guided part, run.sh --guided)
VET.MANUAL = {
    -- these three are tried with real key presses (drive steps), MANUAL only if that failed
    ["GearChanged:player"] = "needs a driver pressing W / S",
    ["ShiftedIntoReverse:player"] = "needs a driver holding S",
    ["ShiftedOutOfReverse:player"] = "needs a driver releasing S",
    ["WentOffroad:player"] = "needs a driver leaving the road",
    ["BackOnRoad:player"] = "needs a driver coming back on the road",
}

function VET.fullName(name, side)
    if side == "player" then return VE.PLAYER_PREFIX .. name end
    return VE.WORLD_PREFIX .. name
end

-- calls fn(name, side) for every event and side in the list
function VET.forEachEvent(fn)
    for name, sides in pairs(VET.EVENTS) do
        if string.find(sides, "p", 1, true) then fn(name, "player") end
        if string.find(sides, "w", 1, true) then fn(name, "world") end
    end
end

------------------------------------------------------------------------
-- log: console.txt and <cachedir>/Lua/VehicleEventsTest_<side>.log
------------------------------------------------------------------------

VET.LOG_FILE = "VehicleEventsTest_" .. VET.SIDE .. ".log"

function VET.resetLog()
    local writer = getFileWriter(VET.LOG_FILE, true, false)
    if writer then writer:close() end
end

function VET.log(text)
    print("[VET] " .. text)
    local writer = getFileWriter(VET.LOG_FILE, true, true)
    if writer then
        writer:write(text .. "\n")
        writer:close()
    end
end

function VET.writeFile(name, text)
    local writer = getFileWriter(name, true, false)
    if writer then
        writer:write(text)
        writer:close()
    end
end

-- first line of a file in <cachedir>/Lua, nil if missing or empty
function VET.readLine(name)
    local reader = getFileReader(name, false)
    if not reader then return nil end
    local line = reader:readLine()
    reader:close()
    if line == nil or line == "" then return nil end
    return line
end

------------------------------------------------------------------------
-- arguments as text, so the server can send them and both sides compare the same way
------------------------------------------------------------------------

function VET.describe(value)
    if value == nil then return "nil" end
    if type(value) == "number" then
        if value == math.floor(value) then return string.format("%d", value) end
        return string.format("%.2f", value)
    end
    if type(value) == "boolean" or type(value) == "string" then return tostring(value) end
    if instanceof(value, "BaseVehicle") then return "vehicle:" .. tostring(value:getId()) end
    if instanceof(value, "IsoPlayer") then return "player:" .. tostring(value:getUsername()) end
    if instanceof(value, "VehiclePart") then
        local vehicle = value:getVehicle()
        return "part:" .. tostring(value:getId()) .. "@" .. tostring(vehicle and vehicle:getId())
    end
    if instanceof(value, "InventoryItem") then return "item:" .. tostring(value:getFullType()) end
    return tostring(value)
end

------------------------------------------------------------------------
-- recorder: one named listener per event, kept so they can be removed (listener gating test)
------------------------------------------------------------------------

VET.listeners = VET.listeners or {}
VET.active = false

local function makeListener(name, side)
    local function onVehicleEvent(...)
        if not VET.active then return end
        local count = select("#", ...)
        local args = { ... }
        local desc = {}
        for i = 1, count do
            desc[i] = VET.describe(args[i])
        end
        VET.onHit({ name = name, side = side, where = VET.SIDE, n = count, desc = desc })
    end
    return onVehicleEvent
end

-- set by the client file (keep the hit) and the server file (send it to the client)
function VET.onHit(hit) end

function VET.listenAll()
    local added = 0
    VET.forEachEvent(function(name, side)
        local full = VET.fullName(name, side)
        if not VET.listeners[full] and Events[full] then
            local listener = makeListener(name, side)
            VET.listeners[full] = listener
            Events[full].Add(listener)
            added = added + 1
        end
    end)
    return added
end

function VET.unlistenAll()
    for full, listener in pairs(VET.listeners) do
        Events[full].Remove(listener)
    end
    VET.listeners = {}
end

-- the API's own -debug printers count as listeners too, so the gating test removes them as well
function VET.muteDebugPrinters(mute)
    for full, printer in pairs(VE.debugPrinters or {}) do
        if mute then
            Events[full].Remove(printer)
        else
            Events[full].Add(printer)
        end
    end
end

-- README list vs what the API registered, both ways
function VET.checkNames()
    local problems = {}
    VET.forEachEvent(function(name, side)
        local full = VET.fullName(name, side)
        if not Events[full] then problems[#problems + 1] = "missing " .. full end
    end)
    for full in pairs(VE.eventOwners) do
        local name, side
        if string.sub(full, 1, #VE.PLAYER_PREFIX) == VE.PLAYER_PREFIX then
            name, side = string.sub(full, #VE.PLAYER_PREFIX + 1), "p"
        else
            name, side = string.sub(full, #VE.WORLD_PREFIX + 1), "w"
        end
        local sides = VET.EVENTS[name]
        if not sides or not string.find(sides, side, 1, true) then
            problems[#problems + 1] = "not in README " .. full
        end
    end
    return problems
end

------------------------------------------------------------------------
-- car helpers. Run where the car is decided: SP, or the server in MP.
-- the transmit calls do nothing in SP
------------------------------------------------------------------------

local H = {}
VET.H = H

-- items taken out by a step, put back by the next one
VET.saved = VET.saved or {}

function H.part(car, id)
    local part = car:getPartById(id)
    if not part then error("no part " .. id .. " on " .. tostring(car:getScriptName())) end
    return part
end

function H.setFuel(car, fraction)
    local tank = H.part(car, "GasTank")
    tank:setContainerContentAmount(tank:getContainerCapacity() * fraction)
    car:transmitPartModData(tank)
end

function H.setBattery(car, charge)
    local battery = H.part(car, "Battery")
    battery:getInventoryItem():setUsedDelta(charge)
    car:transmitPartUsedDelta(battery)
end

function H.setCondition(car, id, condition)
    local part = H.part(car, id)
    part:setCondition(condition)
    local item = part:getInventoryItem()
    if item then
        item:setCondition(condition)
        part:doInventoryItemStats(item, part:getMechanicSkillInstaller())
    end
    car:transmitPartCondition(part)
    car:transmitPartItem(part)
end

function H.removePart(car, id)
    local part = H.part(car, id)
    VET.saved[id] = part:getInventoryItem()
    part:setInventoryItem(nil)
    if part:getWheelIndex() ~= -1 then car:setTireRemoved(part:getWheelIndex(), true) end
    car:transmitPartItem(part)
end

function H.installPart(car, id)
    local part = H.part(car, id)
    local item = VET.saved[id]
    if not item then error("nothing saved for " .. id) end
    VET.saved[id] = nil
    item:setCondition(100)
    part:setInventoryItem(item, 10)
    part:setCondition(100)
    if part:getWheelIndex() ~= -1 then
        car:setTireRemoved(part:getWheelIndex(), false)
        part:setContainerContentAmount(part:getContainerCapacity(), true, true)
        -- physics only: a dedicated server has no Bullet native for it
        if not isServer() then car:setTireInflation(part:getWheelIndex(), 1) end
        car:transmitPartModData(part)
    end
    car:transmitPartItem(part)
    car:transmitPartCondition(part)
end

function H.setTireAir(car, id, fraction)
    local tire = H.part(car, id)
    tire:setContainerContentAmount(tire:getContainerCapacity() * fraction, true, true)
    if not isServer() then car:setTireInflation(tire:getWheelIndex(), fraction) end
    car:transmitPartModData(tire)
end

function H.setDoor(car, id, open)
    local part = H.part(car, id)
    part:getDoor():setOpen(open)
    car:transmitPartDoor(part)
end

function H.setDoorLocked(car, id, locked)
    local part = H.part(car, id)
    part:getDoor():setLocked(locked)
    car:transmitPartDoor(part)
end

function H.setWindowOpen(car, id, open)
    local part = H.part(car, id)
    local window = part:getWindow()
    window:setOpen(open)
    window:setOpenDelta(open and 1 or 0)
    car:transmitPartWindow(part)
end

function H.setHeater(car, on)
    local heater = H.part(car, "Heater")
    heater:getModData().active = on
    heater:getModData().temperature = on and 20 or 0
    car:transmitPartModData(heater)
end

-- every flag back to a known state, so a step only sees its own change
function H.resetCar(car)
    car:repair()
    H.setFuel(car, 1)
    H.setBattery(car, 1)
    car:engineDoIdle()
    car:setHeadlightsOn(false)
    car:setLightbarLightsMode(0)
    car:setLightbarSirenMode(0)
    car:setAlarmed(false)
    car:transmitAlarmed()
    car:cheatHotwire(false, false)
    car:setTrunkLocked(false)
    for p = 0, car:getPartCount() - 1 do
        local part = car:getPartByIndex(p)
        if part:getDoor() then
            part:getDoor():setLocked(false)
            part:getDoor():setOpen(false)
            car:transmitPartDoor(part)
        end
        if part:getWindow() then
            part:getWindow():setOpen(false)
            part:getWindow():setOpenDelta(0)
            car:transmitPartWindow(part)
        end
    end
    H.setHeater(car, false)
    car:setPreviouslyEntered(false)
    car:transmitAlarmed()
end

------------------------------------------------------------------------
-- the steps
-- where: "car"    = where the car is decided (SP local, MP server)
--        "client" = the local player's side (SP local, MP client)
--        "manual" = a person does it (guided part only)
-- expect: event names, or { name, values = {new, old}, on = "trailer", count = n, sides = "pw" }
--   values: "$car" / "$trailer" / "$player" are replaced, "*" = anything, "+" = bigger than old
-- allow: other events that may fire because of the same change (logged, not a failure)
-- strict: any other event fails the step
------------------------------------------------------------------------

VET.STEPS = {}
local function step(def)
    VET.STEPS[#VET.STEPS + 1] = def
    VET.STEPS[def.id] = def
end

-- a street spot is found by the client, the car side spawns there
step({ id = "spawn", title = "Spawn the test car", where = "car", setup = true,
    act = function(c, args)
        local sq = getCell():getGridSquare(args.x, args.y, 0)
        if not sq then
            local p = c.player
            local mine = p and getCell():getGridSquare(math.floor(p:getX()), math.floor(p:getY()), 0)
            -- not an error(): the client tries again, and a Lua error would show in the console scan
            return { notLoaded = "square " .. tostring(args.x) .. "," .. tostring(args.y) .. " not loaded (player at "
                .. (p and (math.floor(p:getX()) .. "," .. math.floor(p:getY())) or "?")
                .. ", player square " .. (mine and "loaded" or "not loaded") .. ")" }
        end
        local car = addVehicleDebug("Base.CarLightsPolice", IsoDirections.E, nil, sq)
        if not car then error("addVehicleDebug returned nil") end
        H.resetCar(car)
        return { car = car:getId() }
    end })

step({ id = "reset", title = "Put the car in a known state", where = "car", setup = true,
    act = function(c) H.resetCar(c.car) end })

step({ id = "firstOpened", title = "First opened flag", where = "car",
    act = function(c)
        c.car:setPreviouslyEntered(true)
        c.car:transmitAlarmed()
    end,
    expect = { "FirstOpened" } })

step({ id = "enter", title = "Get in the driver seat", where = "client", seated = true, strict = true,
    act = function(c) VET.H.enter(c.player, c.car, 0) end,
    expect = { { name = "Entered", values = { "0" } }, "BecameOccupied" } })

step({ id = "seatTo1", title = "Move to the passenger seat", where = "client",
    act = function(c) VET.H.switchSeat(c.player, c.car, 0, 1) end,
    expect = { { name = "SeatChanged", values = { "1", "0" } } } })

step({ id = "seatTo0", title = "Back to the driver seat", where = "client",
    act = function(c) VET.H.switchSeat(c.player, c.car, 1, 0) end,
    expect = { { name = "SeatChanged", values = { "0", "1" } } } })

step({ id = "engineOn", title = "Engine starts", where = "car",
    act = function(c) c.car:engineDoRunning() end,
    expect = { "EngineStarted", { name = "EngineStateChanged", values = { "Running", "Idle" } } } })

step({ id = "engineOff", title = "Engine stops", where = "car",
    act = function(c) c.car:engineDoIdle() end,
    expect = { "EngineStopped", { name = "EngineStateChanged", values = { "Idle", "Running" } } },
    allow = { "HeaterTurnedOff" } })

step({ id = "engineFail", title = "Engine fails to start", where = "car", timeout = 10000,
    act = function(c) c.car:engineDoStartingFailed() end,
    expect = { { name = "EngineStateChanged", count = 2 } } })

step({ id = "headlightsOn", title = "Headlights on", where = "car",
    act = function(c) c.car:setHeadlightsOn(true) end, expect = { "HeadlightsTurnedOn" } })
step({ id = "headlightsOff", title = "Headlights off", where = "car",
    act = function(c) c.car:setHeadlightsOn(false) end, expect = { "HeadlightsTurnedOff" } })

step({ id = "lightbarOn", title = "Police lights on", where = "car",
    act = function(c) c.car:setLightbarLightsMode(2) end, expect = { "LightbarTurnedOn" } })
step({ id = "sirenOn", title = "Siren on", where = "car",
    act = function(c)
        c.car:setSirenStartTime(getGameTime():getWorldAgeHours())
        c.car:setLightbarSirenMode(1)
    end,
    expect = { "SirenTurnedOn" } })
step({ id = "sirenOff", title = "Siren off", where = "car",
    act = function(c) c.car:setLightbarSirenMode(0) end, expect = { "SirenTurnedOff" } })
step({ id = "lightbarOff", title = "Police lights off", where = "car",
    act = function(c) c.car:setLightbarLightsMode(0) end, expect = { "LightbarTurnedOff" } })

step({ id = "heaterOn", title = "Heater on", where = "car",
    act = function(c) H.setHeater(c.car, true) end, expect = { "HeaterTurnedOn" } })
step({ id = "heaterOff", title = "Heater off", where = "car",
    act = function(c) H.setHeater(c.car, false) end, expect = { "HeaterTurnedOff" } })

-- the radio is driven by the client in vanilla too
step({ id = "radioOn", title = "Radio on", where = "client",
    act = function(c) VET.H.setRadio(c.car, true) end, expect = { "RadioTurnedOn" } })
step({ id = "radioOff", title = "Radio off", where = "client",
    act = function(c) VET.H.setRadio(c.car, false) end, expect = { "RadioTurnedOff" } })

step({ id = "hornOn", title = "Horn starts", where = "car",
    act = function(c) c.car:onHornStart() end, expect = { "HornStarted" } })
step({ id = "hornOff", title = "Horn stops", where = "car",
    act = function(c) c.car:onHornStop() end, expect = { "HornStopped" } })

-- cruise control on / off is only on the driver's client, never sent anywhere
step({ id = "cruiseOn", title = "Cruise control on", where = "client",
    act = function(c) c.car:setRegulator(true) end, expect = { "CruiseControlTurnedOn" } })
step({ id = "cruiseOff", title = "Cruise control off", where = "client",
    act = function(c) c.car:setRegulator(false) end, expect = { "CruiseControlTurnedOff" } })

step({ id = "keyIn", title = "Key in the ignition", where = "car",
    act = function(c)
        local key = c.car:createVehicleKey()
        c.car:setCurrentKey(key)
        c.car:transmitAlarmed()
    end,
    expect = { "IgnitionKeyInserted" } })
step({ id = "keyOut", title = "Key out of the ignition", where = "car",
    act = function(c)
        local key = c.car:getCurrentKey()
        if not key then error("no key in the ignition") end
        key:getContainer():DoRemoveItem(key)
        c.car:transmitAlarmed()
    end,
    expect = { "IgnitionKeyRemoved" } })

step({ id = "hotwire", title = "Hotwired", where = "car",
    act = function(c) c.car:cheatHotwire(true, false) end, expect = { "Hotwired" } })
step({ id = "hotwireBreak", title = "Hotwire breaks", where = "car",
    act = function(c) c.car:cheatHotwire(true, true) end, expect = { "HotwireBroken" } })
step({ id = "hotwireUndo", title = "Hotwire removed and repaired", where = "car",
    act = function(c) c.car:cheatHotwire(false, false) end, expect = { "HotwireRemoved", "HotwireRepaired" } })

step({ id = "doorLock", title = "Lock the front right door", where = "car",
    act = function(c) H.setDoorLocked(c.car, "DoorFrontRight", true) end,
    expect = { { name = "DoorLocked", part = "DoorFrontRight" }, "AnyDoorLocked" } })
step({ id = "doorUnlock", title = "Unlock it", where = "car",
    act = function(c) H.setDoorLocked(c.car, "DoorFrontRight", false) end,
    expect = { { name = "DoorUnlocked", part = "DoorFrontRight" }, "AllDoorsUnlocked" } })

step({ id = "trunkLock", title = "Lock the trunk", where = "car",
    act = function(c) c.car:setTrunkLocked(true) end,
    expect = { "TrunkLocked" }, allow = { "DoorLocked" } })
step({ id = "trunkUnlock", title = "Unlock the trunk", where = "car",
    act = function(c) c.car:setTrunkLocked(false) end,
    expect = { "TrunkUnlocked" }, allow = { "DoorUnlocked" } })

step({ id = "doorOpen", title = "Open the front right door", where = "car",
    act = function(c) H.setDoor(c.car, "DoorFrontRight", true) end,
    expect = { { name = "DoorOpened", part = "DoorFrontRight" } } })
step({ id = "doorClose", title = "Close it", where = "car",
    act = function(c) H.setDoor(c.car, "DoorFrontRight", false) end,
    expect = { { name = "DoorClosed", part = "DoorFrontRight" } } })

step({ id = "windowOpen", title = "Roll the front right window down", where = "car",
    act = function(c) H.setWindowOpen(c.car, "WindowFrontRight", true) end,
    expect = { { name = "WindowOpened", part = "WindowFrontRight" } } })
step({ id = "windowClose", title = "Roll it up", where = "car",
    act = function(c) H.setWindowOpen(c.car, "WindowFrontRight", false) end,
    expect = { { name = "WindowClosed", part = "WindowFrontRight" } } })

step({ id = "windowSmash", title = "Smash the rear left window", where = "car", timeout = 10000,
    act = function(c)
        local part = H.part(c.car, "WindowRearLeft")
        VET.saved.WindowRearLeft = part:getInventoryItem()
        part:getWindow():damage(100)
    end,
    expect = { { name = "WindowSmashed", part = "WindowRearLeft" } },
    allow = { "PartRemoved", "PartConditionChanged" } })
step({ id = "windowRepair", title = "Repair it", where = "car", timeout = 10000,
    act = function(c) H.installPart(c.car, "WindowRearLeft") end,
    expect = { { name = "WindowRepaired", part = "WindowRearLeft" } },
    allow = { "PartInstalled", "PartConditionChanged" } })

step({ id = "condition", title = "Muffler condition 100 to 50", where = "car", timeout = 10000,
    act = function(c) H.setCondition(c.car, "Muffler", 50) end,
    expect = { { name = "PartConditionChanged", part = "Muffler", values = { "50", "100" } } } })
step({ id = "conditionBack", title = "Muffler condition back to 100", where = "car", timeout = 10000,
    act = function(c) H.setCondition(c.car, "Muffler", 100) end,
    expect = { { name = "PartConditionChanged", part = "Muffler", values = { "100", "50" } } } })

step({ id = "partRemove", title = "Take the muffler out", where = "car", timeout = 10000,
    act = function(c) H.removePart(c.car, "Muffler") end,
    expect = { { name = "PartRemoved", part = "Muffler", values = { "nil", "item:*" } } },
    allow = { "PartConditionChanged" } })
step({ id = "partInstall", title = "Put it back", where = "car", timeout = 10000,
    act = function(c) H.installPart(c.car, "Muffler") end,
    expect = { { name = "PartInstalled", part = "Muffler", values = { "item:*", "nil" } } },
    allow = { "PartConditionChanged" } })

step({ id = "tireFlat", title = "Front right tire loses its air", where = "car", timeout = 10000,
    act = function(c) H.setTireAir(c.car, "TireFrontRight", 0) end,
    expect = { { name = "TireWentFlat", part = "TireFrontRight" } } })
step({ id = "tireAir", title = "Pump it back", where = "car", timeout = 10000,
    act = function(c) H.setTireAir(c.car, "TireFrontRight", 1) end,
    expect = { { name = "TireInflated", part = "TireFrontRight" } } })

step({ id = "tireRemove", title = "Take the rear left tire off", where = "car", timeout = 10000,
    act = function(c) H.removePart(c.car, "TireRearLeft") end,
    expect = { "TireMissing", { name = "PartRemoved", part = "TireRearLeft" } },
    allow = { "PartConditionChanged", "BrokeDown" } })
step({ id = "tireInstall", title = "Put it back", where = "car", timeout = 10000,
    act = function(c) H.installPart(c.car, "TireRearLeft") end,
    expect = { "AllTiresInstalled", { name = "PartInstalled", part = "TireRearLeft" } },
    allow = { "PartConditionChanged", "BecameDriveable", "TireInflated" } })

step({ id = "fuelLow", title = "Fuel at 10%", where = "car",
    act = function(c) H.setFuel(c.car, 0.1) end, expect = { "FuelLow" } })
step({ id = "fuelEmpty", title = "Fuel at 0", where = "car", timeout = 10000,
    act = function(c) H.setFuel(c.car, 0) end, expect = { "FuelEmpty", "BrokeDown" } })
step({ id = "fuelFull", title = "Fuel back to full", where = "car", timeout = 10000,
    act = function(c) H.setFuel(c.car, 1) end,
    expect = { "FuelRefilled", "FuelNoLongerLow", "BecameDriveable" } })

step({ id = "batteryLow", title = "Battery at 10%", where = "car",
    act = function(c) H.setBattery(c.car, 0.1) end, expect = { "BatteryLow" } })
step({ id = "batteryDead", title = "Battery at 0", where = "car",
    act = function(c) H.setBattery(c.car, 0) end, expect = { "PowerLost" } })
step({ id = "batteryFull", title = "Battery back to full", where = "car",
    act = function(c) H.setBattery(c.car, 1) end, expect = { "PowerRestored", "BatteryNoLongerLow" } })

step({ id = "engineBroken", title = "Engine condition 0", where = "car", timeout = 10000,
    act = function(c) H.setCondition(c.car, "Engine", 0) end,
    expect = { "BrokeDown" }, allow = { "PartConditionChanged" } })
step({ id = "engineFixed", title = "Engine condition back to 100", where = "car", timeout = 10000,
    act = function(c) H.setCondition(c.car, "Engine", 100) end,
    expect = { "BecameDriveable" }, allow = { "PartConditionChanged" } })

step({ id = "alarmArm", title = "Arm the alarm", where = "car",
    act = function(c)
        c.car:setAlarmed(true)
        c.car:transmitAlarmed()
    end,
    expect = { "AlarmArmed" } })
step({ id = "alarmDisarm", title = "Disarm it", where = "car",
    act = function(c)
        c.car:setAlarmed(false)
        c.car:transmitAlarmed()
    end,
    expect = { "AlarmDisarmed" } })
-- triggerAlarm clears the armed flag (README: AlarmDisarmed also fires when it goes off)
step({ id = "alarmRing", title = "Alarm goes off", where = "car",
    act = function(c)
        c.car:setAlarmed(true)
        c.car:triggerAlarm()
    end,
    expect = { "AlarmStartedRinging" },
    allow = { "AlarmArmed", "AlarmDisarmed", "HeadlightsTurnedOn", "HeadlightsTurnedOff" } })
-- no Lua way to stop the alarm, it stops when the battery is dead
step({ id = "alarmStop", title = "Alarm stops (battery dead)", where = "car",
    act = function(c) H.setBattery(c.car, 0) end,
    expect = { "AlarmStoppedRinging", "PowerLost" },
    allow = { "BatteryLow", "HeadlightsTurnedOn", "HeadlightsTurnedOff" } })
step({ id = "alarmReset", title = "Battery back, lights off", where = "car",
    act = function(c)
        H.setBattery(c.car, 1)
        c.car:setHeadlightsOn(false)
    end,
    expect = { "PowerRestored" },
    allow = { "BatteryNoLongerLow", "HeadlightsTurnedOff" } })

step({ id = "cargoIn", title = "Put a sledgehammer in the trunk", where = "car", timeout = 10000,
    act = function(c)
        local container = H.part(c.car, "TruckBed"):getItemContainer()
        local item = container:AddItem("Base.Sledgehammer")
        VET.saved.cargo = item
        if isServer() then sendAddItemToContainer(container, item) end
    end,
    expect = { { name = "CargoChanged", values = { "+", "*" } } } })
step({ id = "cargoOut", title = "Take it out", where = "car", timeout = 10000,
    act = function(c)
        local container = H.part(c.car, "TruckBed"):getItemContainer()
        local item = VET.saved.cargo
        VET.saved.cargo = nil
        container:DoRemoveItem(item)
        if isServer() then sendRemoveItemFromContainer(container, item) end
    end,
    expect = { { name = "CargoChanged", values = { "-", "*" } } } })

step({ id = "trailerSpawn", title = "Spawn a livestock trailer behind", where = "car", timeout = 4000,
    act = function(c)
        local sq = c.car:getSquare()
        local trailerSq = getCell():getGridSquare(sq:getX() - 6, sq:getY(), 0)
        local trailer = addVehicleDebug("Base.Trailer_Livestock", IsoDirections.E, nil, trailerSq)
        if not trailer then error("trailer spawn failed") end
        trailer:repair()
        return { trailer = trailer:getId() }
    end,
    expect = {}, allow = { "StartedMoving", "StoppedMoving" } })

step({ id = "tow", title = "Hook the trailer", where = "car", timeout = 10000,
    act = function(c)
        if not c.trailer then error("trailer not found") end
        if isServer() then
            -- positionTrailer moves the trailer on the server only: the client's physics still has
            -- it at the old spot and the link breaks at once. Hook it where it is, like the vanilla
            -- attachTrailer command (it spawned right behind the hitch)
            c.car:addPointConstraint(c.player, c.trailer, "trailer", "trailer")
        else
            c.car:positionTrailer(c.trailer)
        end
    end,
    expect = { { name = "StartedTowing", values = { "$trailer", "nil" } },
        { name = "StartedBeingTowed", on = "trailer", values = { "$car", "nil" }, sides = "w" } },
    -- hooking up knocks the car about: in MP the part damage comes in several syncs
    many = true, allow = { "StartedMoving", "StoppedMoving", "PartConditionChanged" } })

step({ id = "animal", title = "A cow in the trailer", where = "car", timeout = 10000,
    act = function(c)
        local def = AnimalDefinitions.getDef("cow")
        local breeds = def and def:getBreeds()
        if not breeds or breeds:isEmpty() then error("no cow breed") end
        if not c.trailer then error("trailer not found") end
        local sq = c.trailer:getSquare()
        local cow = addAnimal(getCell(), sq:getX(), sq:getY(), 0, "cow", breeds:get(0))
        cow:addToWorld()
        if not c.trailer:canAddAnimalInTrailer(cow) then error("trailer refuses the cow") end
        c.trailer:addAnimalInTrailer(cow)
    end,
    expect = { { name = "AnimalsChanged", on = "trailer", values = { "+", "*" }, sides = "w" } } })

step({ id = "untow", title = "Unhook the trailer", where = "car", timeout = 10000,
    act = function(c) c.car:breakConstraint(true, false) end,
    expect = { { name = "StoppedTowing", values = { "nil", "$trailer" } },
        { name = "StoppedBeingTowed", on = "trailer", values = { "nil", "$car" }, sides = "w" } },
    allow = { "StartedMoving", "StoppedMoving" } })

step({ id = "trailerGone", title = "Delete the trailer", where = "car", timeout = 10000,
    act = function(c)
        if not c.trailer then error("trailer not found") end
        c.trailer:permanentlyRemove()
    end,
    expect = { { name = "Unloaded", on = "trailer", sides = "w" } } })

step({ id = "towerSpawn", title = "Spawn a second car in front", where = "car", timeout = 4000,
    act = function(c)
        local sq = c.car:getSquare()
        local towerSq = getCell():getGridSquare(sq:getX() + 7, sq:getY(), 0)
        local tower = addVehicleDebug("Base.CarLightsPolice", IsoDirections.E, nil, towerSq)
        if not tower then error("second car spawn failed") end
        tower:repair()
        return { tower = tower:getId() }
    end,
    expect = {}, allow = { "StartedMoving", "StoppedMoving" } })

-- a car with a driver towed by an empty car gets swapped by the game at once (CarController.java:244):
-- the driven car becomes the tower. So the player sits as a passenger while being towed
step({ id = "towSeat", title = "Move to the passenger seat for the tow", where = "client",
    act = function(c) VET.H.switchSeat(c.player, c.car, 0, 1) end,
    expect = { { name = "SeatChanged", values = { "1", "0" } } } })

step({ id = "towedBy", title = "The second car tows ours", where = "car", timeout = 10000,
    act = function(c)
        if not c.tower then error("second car not found") end
        c.tower:addPointConstraint(nil, c.car, "trailer", "trailerfront")
    end,
    expect = { { name = "StartedBeingTowed", values = { "$tower", "nil" } },
        { name = "StartedTowing", on = "tower", values = { "$car", "nil" }, sides = "w" } },
    allow = { "StartedMoving", "StoppedMoving", "PartConditionChanged", "WindowSmashed", "PartRemoved" } })

step({ id = "untowedBy", title = "Unhook it", where = "car", timeout = 10000,
    act = function(c)
        if not c.tower then error("second car not found") end
        c.tower:breakConstraint(true, false)
    end,
    expect = { { name = "StoppedBeingTowed", values = { "nil", "$tower" } },
        { name = "StoppedTowing", on = "tower", values = { "nil", "$car" }, sides = "w" } },
    allow = { "StartedMoving", "StoppedMoving", "PartConditionChanged", "WindowSmashed", "PartRemoved" } })

step({ id = "towerGone", title = "Delete the second car", where = "car", timeout = 10000,
    act = function(c)
        if not c.tower then error("second car not found") end
        c.tower:permanentlyRemove()
    end,
    expect = { { name = "Unloaded", on = "tower", sides = "w" } } })

step({ id = "towSeatBack", title = "Back to the driver seat", where = "client",
    act = function(c) VET.H.switchSeat(c.player, c.car, 1, 0) end,
    expect = { { name = "SeatChanged", values = { "0", "1" } } } })

-- the player drives for real: engine on, then run.sh holds W / S in the game window (no Lua way,
-- CarController reads the keyboard). The world check runs every tick meanwhile (car side: the
-- server in MP), then back to 100 ms. If the keys don't reach the game (window not focused),
-- these steps end as MANUAL: run --guided.
step({ id = "fastWorld", title = "World check every tick", where = "car", setup = true,
    act = function(c)
        SandboxVars.VehicleEvents = SandboxVars.VehicleEvents or {}
        SandboxVars.VehicleEvents.WorldCheckMs = 1
    end })
step({ id = "driveEngine", title = "Engine on to drive", where = "car",
    act = function(c) c.car:engineDoRunning() end,
    expect = { "EngineStarted" }, allow = { "EngineStateChanged" } })
step({ id = "driveForward", title = "Hold W, let go, roll to a stop", where = "client", timeout = 25000,
    tryAuto = true, trace = true, many = true,
    act = function(c) VET.H.pressKeys("w 1500") end,
    -- driving wears the tires a little (PartConditionChanged)
    expect = { "GearChanged", "StartedMoving", "StoppedMoving" },
    allow = { "WentOffroad", "BackOnRoad", "PartConditionChanged" } })
step({ id = "driveReverse", title = "Hold S until it backs up, let go, it goes back to neutral", where = "client", timeout = 25000,
    tryAuto = true, trace = true, many = true,
    act = function(c) VET.H.pressKeys("s 1500") end,
    -- once stopped with S let go, the gearbox goes back to neutral on its own: ShiftedOutOfReverse
    expect = { "ShiftedIntoReverse", "StartedMoving", "StoppedMoving", "ShiftedOutOfReverse" },
    allow = { "GearChanged", "WentOffroad", "BackOnRoad", "PartConditionChanged" } })
step({ id = "driveEngineOff", title = "Engine off after driving", where = "car",
    act = function(c) c.car:engineDoIdle() end,
    expect = { "EngineStopped" }, allow = { "EngineStateChanged", "StoppedMoving" } })
step({ id = "normalWorld", title = "World check back to 100 ms", where = "car", setup = true,
    act = function(c) SandboxVars.VehicleEvents.WorldCheckMs = 100 end })

-- last of the car moves: the flip leaves the physics unsettled for a while
step({ id = "flip", title = "Car on its roof", where = "client", timeout = 8000, tryAuto = true,
    act = function(c) VET.H.flip(c.car) end,
    expect = { "Flipped" }, allow = { "StartedMoving", "StoppedMoving" } })
step({ id = "unflip", title = "Car back on its wheels", where = "client", timeout = 8000, tryAuto = true,
    act = function(c) VET.H.unflip(c.car) end,
    expect = { "BackOnWheels" }, allow = { "StartedMoving", "StoppedMoving" } })
-- wait for the car to stop rocking, so the strict steps after this only see their own events
step({ id = "settle", title = "Let the car settle", where = "client", timeout = 8000,
    -- physics off: no more rocking, the speed reads 0. It wakes up again on its own when touched
    act = function(c) c.car:setPhysicsActive(false) end,
    expect = {}, allow = { "StartedMoving", "StoppedMoving", "Flipped", "BackOnWheels", "WentOffroad", "BackOnRoad" } })

-- nobody listens: a change must fire nothing, and nothing late once listeners come back
step({ id = "gating", title = "No listener, no event", where = "client", special = "gating", timeout = 12000,
    expect = { "HeadlightsTurnedOff" } })

-- reloading the player file while seated must not fire Entered again
step({ id = "reload", title = "Reload the API files while seated", where = "client", special = "reload",
    strict = true, timeout = 4000, expect = {} })

step({ id = "exit", title = "Get out", where = "client", seated = false,
    act = function(c) VET.H.exit(c.player, c.car) end,
    expect = { { name = "Exited", values = { "0" } }, "BecameEmpty" } })

-- engine already running when you get in: only Entered on the player side (README, Timing)
step({ id = "engineOnOutside", title = "Start the engine from outside", where = "car",
    act = function(c) c.car:engineDoRunning() end,
    expect = { "EngineStarted", { name = "EngineStateChanged", values = { "Running", "Idle" } } } })
step({ id = "enterRunning", title = "Get in the running car", where = "client", seated = true, strict = true, trace = true,
    act = function(c) VET.H.enter(c.player, c.car, 0) end,
    expect = { { name = "Entered", values = { "0" } }, "BecameOccupied" } })
step({ id = "exitRunning", title = "Get out again", where = "client", seated = false,
    act = function(c) VET.H.exit(c.player, c.car) end,
    expect = { { name = "Exited", values = { "0" } }, "BecameEmpty" } })
step({ id = "engineOffOutside", title = "Stop the engine", where = "car",
    act = function(c) c.car:engineDoIdle() end,
    expect = { "EngineStopped", "EngineStateChanged" }, allow = { "HeaterTurnedOff" } })

-- the car's chunk unloads when the player goes far away
step({ id = "chunkUnload", title = "Walk far away (chunk unload)", where = "client", special = "farAway",
    timeout = 90000, expect = { "Unloaded" } })
-- a car loading back in fires nothing (README, Timing)
step({ id = "comeBack", title = "Come back", where = "client", special = "comeBack", timeout = 30000,
    strict = true, expect = {}, allow = { "StartedMoving", "StoppedMoving" } })

-- last: the player dies in the car
step({ id = "enterToDie", title = "Get in once more", where = "client", seated = true,
    act = function(c) VET.H.enter(c.player, c.car, 0) end,
    expect = { { name = "Entered", values = { "0" } }, "BecameOccupied" } })
step({ id = "death", title = "Die in the car", where = "client", seated = false, special = "death",
    timeout = 10000,
    expect = { { name = "Exited", values = { "0" } }, "BecameEmpty" } })

-- guided part: a person drives (run.sh --guided). Moving is here too if the push failed
-- what a person does in --guided: going offroad and back can't be aimed with blind key presses
-- (gears and reverse are driven by the drive steps with real keys)
local DRIVING = { "GearChanged", "ShiftedIntoReverse", "ShiftedOutOfReverse", "StartedMoving", "StoppedMoving",
    "PartConditionChanged" }
VET.GUIDED = {
    { id = "offroad", title = "Drive onto the grass",
        expect = { "WentOffroad" }, allow = DRIVING },
    { id = "onroad", title = "Drive back onto the road",
        expect = { "BackOnRoad" }, allow = DRIVING },
    { id = "stop", title = "Stop the car",
        -- braking with S can back the car up a bit before it stops
        expect = { "StoppedMoving" }, allow = DRIVING },
}
