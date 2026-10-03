-- VehicleEventsTest server (MP only): runs the car side of the steps for the test client,
-- records the world events and sends each one to that client. Log: <cachedir>/Lua/VehicleEventsTest_server.log
if not isServer() then return end
require "VehicleEventsTest"

VET.testPlayer = nil

local function forwardHit(hit)
    VET.log(string.format("    > %s %s(%s)", hit.side, hit.name, table.concat(hit.desc, ", ")))
    if VET.testPlayer then sendServerCommand(VET.testPlayer, "VET", "hit", hit) end
end
VET.onHit = forwardHit

local function findLoadedLua(fileName)
    for i = 0, getLoadedLuaCount() - 1 do
        local path = getLoadedLua(i)
        if string.sub(path, -#fileName) == fileName then return path end
    end
    return nil
end

local function onClientCommand(module, command, player, args)
    if module ~= "VET" then return end

    if command == "begin" then
        -- the client resends begin until it hears ready: a late copy must not restart the log
        if VET.active and VET.testPlayer == player then
            sendServerCommand(player, "VET", "ready", { added = 0, problems = "" })
            return
        end
        VET.testPlayer = player
        VET.active = true
        VET.resetLog()
        VET.log("VehicleEventsTest server, test player " .. tostring(player:getUsername()))
        local added = VET.listenAll()
        SandboxVars.VehicleEvents = SandboxVars.VehicleEvents or {}
        SandboxVars.VehicleEvents.WorldCheckMs = 100
        local problems = VET.checkNames()
        VET.log("listening to " .. added .. " events, names: " .. (#problems == 0 and "ok" or table.concat(problems, "; ")))
        sendServerCommand(player, "VET", "ready", { added = added, problems = table.concat(problems, "; ") })

    elseif command == "act" then
        local def = VET.STEPS[args.step]
        local ctx = {
            player = player,
            car = args.car and getVehicleById(args.car) or nil,
            trailer = args.trailer and getVehicleById(args.trailer) or nil,
            tower = args.tower and getVehicleById(args.tower) or nil,
        }
        local ok, res
        if not def or not def.act then
            ok, res = false, "unknown step " .. tostring(args.step)
        elseif not ctx.car and args.step ~= "spawn" then
            ok, res = false, "car " .. tostring(args.car) .. " not found on the server"
        else
            ok, res = pcall(def.act, ctx, args)
        end
        VET.log("== " .. tostring(args.step) .. (ok and "" or (" ERROR " .. tostring(res))))
        sendServerCommand(player, "VET", "acted", {
            step = args.step, ok = ok, err = not ok and tostring(res) or nil, result = ok and res or nil })

    elseif command == "listen" then
        VET.listenAll()
        VET.muteDebugPrinters(false)
        VET.log("listeners back, world " .. tostring(VehicleEvents.sideListeners.world))

    elseif command == "unlisten" then
        VET.unlistenAll()
        VET.muteDebugPrinters(true)
        VET.log("listeners removed, world " .. tostring(VehicleEvents.sideListeners.world))

    elseif command == "reload" then
        local path = findLoadedLua("VehicleEvents_World.lua")
        if path then
            reloadLuaFile(path)
            VET.log("reloaded " .. path)
        else
            VET.log("VehicleEvents_World.lua not in the loaded list")
        end

    elseif command == "trace" then
        VET.traceCar = args and args.car and getVehicleById(args.car) or nil
        VET.lastTrace = nil

    elseif command == "done" then
        VET.log(tostring(args.summary))
        VET.log("DONE")
        VET.active = false
        VET.testPlayer = nil
    end
end

local function onTick()
    local car = VET.traceCar
    if not car then return end
    local t = getTimestampMs()
    if VET.lastTrace and t - VET.lastTrace < 250 then return end
    VET.lastTrace = t
    local driver = car:getDriver()
    VET.log(string.format("    speed server %.2f km/h, gear %s, engine %s, at %.2f,%.2f, driver %s",
        car:getCurrentAbsoluteSpeedKmHour(), tostring(car:getTransmissionNumber()), tostring(car:isEngineRunning()),
        car:getX(), car:getY(), driver and VET.describe(driver) or "none"))
end
if VET.onTick then Events.OnTick.Remove(VET.onTick) end
VET.onTick = onTick
Events.OnTick.Add(onTick)

if VET.onClientCommand then Events.OnClientCommand.Remove(VET.onClientCommand) end
VET.onClientCommand = onClientCommand
Events.OnClientCommand.Add(onClientCommand)
