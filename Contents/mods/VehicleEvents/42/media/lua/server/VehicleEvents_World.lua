-- world events: scans every loaded vehicle where the game runs the engine logic
-- (SP and the MP server, not MP clients)
-- VehicleEvents_OnVehicle<Event>(vehicle, newValue, oldValue), part events (vehicle, part, newValue, oldValue)
-- Entered / Exited (vehicle, character, seat), SeatChanged (vehicle, character, newSeat, oldSeat)
-- Unloaded (vehicle). For loaded use vanilla OnSpawnVehicleEnd
if isClient() then return end
require "VehicleEvents"

local VE = VehicleEvents

VE.WORLD_SLOW_EVERY = VE.WORLD_SLOW_EVERY or 5

VE.worldStates = {}
VE.worldSeen = {}
VE.worldBatch = {}
VE.worldBatchCount = 0
VE.worldBatchIndex = 0 -- 0 = waiting for the next scan
VE.worldScanId = 0
VE.worldLastScan = 0
VE.worldErrorReported = false

local function findSeat(seats, count, character)
    for seat = 0, count - 1 do
        if seats[seat] == character then return seat end
    end
    return -1
end

-- compares who sits where with the last scan
local function checkWorldSeats(vehicle, state, doFire)
    local events = VE.seatEvents.world
    if not VE.anyListeners(events) then
        -- nobody listens: forget seats so the next check only records
        state.seats = nil
        state.nextSeats = nil
        state.seatCount = nil
        return
    end
    if not state.seats then doFire = false end
    local old = state.seats
    local new = state.nextSeats
    if not old then
        old = {}
        new = {}
    end
    local oldCount = state.seatCount or 0
    local count = vehicle:getMaxPassengers()
    for seat = 0, count - 1 do
        new[seat] = vehicle:getCharacter(seat)
    end

    if doFire then
        -- left a seat: moved to another seat or got out
        for seat = 0, oldCount - 1 do
            local character = old[seat]
            if character and new[seat] ~= character then
                local newSeat = findSeat(new, count, character)
                if newSeat >= 0 then
                    if events.seatChanged then triggerEvent(events.seatChanged, vehicle, character, newSeat, seat) end
                elseif events.exited then
                    triggerEvent(events.exited, vehicle, character, seat)
                end
            end
        end
        -- new in a seat and not just moving seats: got in
        for seat = 0, count - 1 do
            local character = new[seat]
            if character and old[seat] ~= character and findSeat(old, oldCount, character) < 0 and events.entered then
                triggerEvent(events.entered, vehicle, character, seat)
            end
        end
    end

    -- swap so both tables get reused next scan
    state.seats = new
    state.nextSeats = old
    state.seatCount = count
end

local function checkWorldVehicle(vehicle, includeSlow)
    local state = VE.worldStates[vehicle]
    local known = state ~= nil
    if not known then
        state = VE.newState()
        VE.worldStates[vehicle] = state
    end

    -- first time we see a car just record it
    checkWorldSeats(vehicle, state, known)
    VE.updateWatchers(state, vehicle, nil, known, includeSlow or not known)
    VE.updateParts(state, vehicle, nil, known, includeSlow or not known)
end

local function forgetUnloaded(scanId)
    local gone = nil
    for vehicle, seen in pairs(VE.worldSeen) do
        if seen ~= scanId then
            gone = gone or {}
            gone[#gone + 1] = vehicle
        end
    end
    if not gone then return end
    for i = 1, #gone do
        local vehicle = gone[i]
        VE.worldSeen[vehicle] = nil
        VE.worldStates[vehicle] = nil
        if VE.loadEvents.unloaded then
            triggerEvent(VE.loadEvents.unloaded, vehicle)
        end
    end
end

-- copy the car list first so a handler that spawns or removes a car cant break the java iterator
local function startScan()
    local batch = VE.worldBatch
    local count = 0
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        count = count + 1
        batch[count] = it:next()
    end
    -- clear what is left from a bigger list so removed cars arent kept in memory
    for i = count + 1, #batch do
        batch[i] = nil
    end
    VE.worldBatchCount = count
    VE.worldBatchIndex = 1
    VE.worldScanId = VE.worldScanId + 1
    VE.worldIncludeSlow = VE.worldScanId % VE.WORLD_SLOW_EVERY == 0
end

local function scanWorldVehicles()
    -- nobody listens to world events: dont scan, start fresh when someone does
    if VE.sideListeners.world == 0 then
        if next(VE.worldSeen) then
            VE.worldStates = {}
            VE.worldSeen = {}
        end
        if VE.worldBatchIndex ~= 0 then
            -- dropped mid scan: let go of the cars left in the list
            local batch = VE.worldBatch
            for i = VE.worldBatchIndex, VE.worldBatchCount do
                batch[i] = nil
            end
            VE.worldBatchIndex = 0
        end
        return
    end

    if VE.worldBatchIndex == 0 then
        local now = getTimestampMs()
        if now - VE.worldLastScan < VE.getSetting("WorldCheckMs") then return end
        VE.worldLastScan = now
        startScan()
    end

    local batch = VE.worldBatch
    local scanId = VE.worldScanId
    -- a scan is spread over several ticks
    local perTick = math.max(1, math.floor(VE.getSetting("WorldCarsPerTick")))
    local last = math.min(VE.worldBatchIndex + perTick - 1, VE.worldBatchCount)
    for i = VE.worldBatchIndex, last do
        local vehicle = batch[i]
        batch[i] = nil
        -- a car removed since the list was made is left out, so it gets Unloaded
        if not vehicle:isRemovedFromWorld() then
            VE.worldSeen[vehicle] = scanId
            -- one broken car must not stop the scan for the others
            local ok, err = pcall(checkWorldVehicle, vehicle, VE.worldIncludeSlow)
            if not ok and not VE.worldErrorReported then
                VE.worldErrorReported = true
                print("[VehicleEvents] ERROR checking vehicle " .. tostring(vehicle:getId()) .. ": " .. tostring(err))
            end
        end
    end
    VE.worldBatchIndex = last + 1

    if VE.worldBatchIndex > VE.worldBatchCount then
        VE.worldBatchIndex = 0
        forgetUnloaded(scanId)
    end
end

if VE.scanWorldVehicles then
    Events.OnTick.Remove(VE.scanWorldVehicles)
end
VE.scanWorldVehicles = scanWorldVehicles
Events.OnTick.Add(scanWorldVehicles)
