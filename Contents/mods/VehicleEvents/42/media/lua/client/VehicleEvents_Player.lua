-- player events: watches the vehicle each local player sits in, every tick
-- VehicleEvents_OnPlayerVehicle<Event>(player, vehicle, newValue, oldValue)
-- part events: (player, part, newValue, oldValue), the vehicle is part:getVehicle()
-- Entered / Exited (player, vehicle, seat), SeatChanged (player, vehicle, newSeat, oldSeat)
require "VehicleEvents"

local VE = VehicleEvents

VE.PLAYER_SLOW_MS = VE.PLAYER_SLOW_MS or 1000

VE.playerLastVehicle = {}
VE.playerLastSeat = {}

-- when this file is reloaded mid-game, start from where the players already sit
-- so a player in a car doesnt get Entered a second time
for i = 0, getNumActivePlayers() - 1 do
    local player = getSpecificPlayer(i)
    if player and player:getVehicle() then
        VE.playerLastVehicle[player] = player:getVehicle()
        VE.playerLastSeat[player] = player:getVehicle():getSeat(player)
    end
end
VE.playerStates = {}
VE.playerLastSlow = {}

-- seats are always tracked (one getSeat call) so a listener added later gets correct events
local function checkPlayerSeat(player, vehicle, lastVehicle)
    local events = VE.seatEvents.player
    local seat = vehicle and vehicle:getSeat(player) or -1
    local lastSeat = VE.playerLastSeat[player]
    VE.playerLastSeat[player] = seat

    if vehicle ~= lastVehicle then
        if lastVehicle and events.exited then
            triggerEvent(events.exited, player, lastVehicle, lastSeat)
        end
        if vehicle and events.entered then
            triggerEvent(events.entered, player, vehicle, seat)
        end
    elseif vehicle and seat ~= lastSeat and events.seatChanged then
        triggerEvent(events.seatChanged, player, vehicle, seat, lastSeat)
    end
end

local function checkPlayerVehicle(player)
    -- a dead player is handled once in onPlayerDeath, dont track it again
    if not player:isLocalPlayer() or player:isDead() then return end

    local vehicle = player:getVehicle()
    local lastVehicle = VE.playerLastVehicle[player]
    local sameVehicle = vehicle ~= nil and vehicle == lastVehicle
    VE.playerLastVehicle[player] = vehicle
    checkPlayerSeat(player, vehicle, lastVehicle)
    if not vehicle then return end

    local state = VE.playerStates[player]
    if not state then
        state = VE.newState()
        VE.playerStates[player] = state
    end

    -- nobody listens to player events: skip, and only record on the next check
    if VE.sideListeners.player == 0 then
        state.skipped = true
        return
    end
    local doFire = sameVehicle and not state.skipped
    state.skipped = false

    local now = getTimestampMs()
    local includeSlow = not sameVehicle or now - (VE.playerLastSlow[player] or 0) >= VE.PLAYER_SLOW_MS
    if includeSlow then
        VE.playerLastSlow[player] = now
    end

    -- new car = just record values so getting in doesnt fire everything
    VE.updateWatchers(state, vehicle, player, doFire, includeSlow or not doFire)
    VE.updateParts(state, vehicle, player, doFire, includeSlow or not doFire)
end

-- the game takes a dead player out of the car right after OnPlayerDeath, without any event:
-- fire Exited here and forget the player (a respawn is a new player object)
local function onPlayerDeath(player)
    if not instanceof(player, "IsoPlayer") or not player:isLocalPlayer() then return end
    local lastVehicle = VE.playerLastVehicle[player]
    local events = VE.seatEvents.player
    if lastVehicle and events.exited then
        triggerEvent(events.exited, player, lastVehicle, VE.playerLastSeat[player])
    end
    VE.playerLastVehicle[player] = nil
    VE.playerLastSeat[player] = nil
    VE.playerStates[player] = nil
    VE.playerLastSlow[player] = nil
end

if VE.checkPlayerVehicle then
    Events.OnPlayerUpdate.Remove(VE.checkPlayerVehicle)
end
VE.checkPlayerVehicle = checkPlayerVehicle
Events.OnPlayerUpdate.Add(checkPlayerVehicle)

if VE.onPlayerDeath then
    Events.OnPlayerDeath.Remove(VE.onPlayerDeath)
end
VE.onPlayerDeath = onPlayerDeath
Events.OnPlayerDeath.Add(onPlayerDeath)
