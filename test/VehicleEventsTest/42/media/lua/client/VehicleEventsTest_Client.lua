-- VehicleEventsTest client: runs the steps (single player, or the MP client with the server file
-- doing the car side), checks every event that fires, writes VehicleEventsTest_<side>.log and
-- VehicleEventsTest_result.txt in <cachedir>/Lua.
-- start by hand from the Lua console: VET.start() / VET.start({ guided = true })
-- run.sh starts it on its own: VehicleEventsTest_auto.txt at the main menu
require "VehicleEventsTest"

local VE = VehicleEvents
local H = VET.H

local QUIET_MS = 1500     -- no event for this long before a step starts
local QUIET_MAX_MS = 15000
local SETTLE_MS = 1500    -- after the expected events, wait this long for doubles
local TIMEOUT_MS = 8000
local ACK_MS = 10000      -- MP: server answer to an action

------------------------------------------------------------------------
-- client side helpers (the player's own actions, same calls as the vanilla timed actions)
------------------------------------------------------------------------

function H.enter(player, car, seat)
    if not car:enter(seat, player) then error("enter refused for seat " .. seat) end
    car:setCharacterPosition(player, seat, "inside")
    car:transmitCharacterPosition(seat, "inside")
    car:playPassengerAnim(seat, "idle")
    triggerEvent("OnEnterVehicle", player)
end

function H.switchSeat(player, car, from, to)
    car:switchSeat(player, to)
    if isClient() then sendSwitchSeat(car, player, from, to) end
    car:playPassengerAnim(to, "idle")
    triggerEvent("OnSwitchVehicleSeat", player)
end

function H.exit(player, car)
    local seat = car:getSeat(player)
    car:exit(player)
    car:setCharacterPosition(player, seat, "outside")
    player:PlayAnim("Idle")
    triggerEvent("OnExitVehicle", player)
end

function H.setRadio(car, on)
    local radio = H.part(car, "Radio")
    radio:getDeviceData():setIsTurnedOn(on)
end

-- one push along x (the car was spawned facing east), about 11 km/h. The driver's brakes stop
-- it within a few frames; bigger or repeated pushes sent the car flying in an earlier run
-- the game reads the real keyboard to drive: run.sh holds the keys in the game window
-- (click.py), keys = "w 1500 none 500 s 2000" (key, ms, ...)
function H.pressKeys(keys)
    VET.writeFile("VehicleEventsTest_keys.txt", keys .. "\n")
end

-- upside down once, physics on: it falls on its roof and stays there
function H.flip(car)
    car:setAngles(0, 0, 180)
    car:setPhysicsActive(true)
end

function H.unflip(car)
    car:flipUpright()
    car:setPhysicsActive(true)
end

function H.teleport(player, x, y)
    if isClient() then
        SendCommandToServer("/teleportto " .. x .. "," .. y .. ",0")
    else
        player:teleportTo(x, y, 0)
    end
end

local function isStreet(sq)
    if not sq or sq:getVehicleContainer() then return false end
    local floor = sq:getFloor()
    local sprite = floor and floor:getSprite()
    local name = sprite and sprite:getName()
    if not name then return false end
    return string.find(name, "street", 1, true) ~= nil
end

-- a 7 x 5 street area near the player, room for the car and the trailer behind it
function H.findStreet(player)
    local cell = getCell()
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    for radius = 2, 70, 2 do
        for dx = -radius, radius, 2 do
            for dy = -radius, radius, 2 do
                local x, y = px + dx, py + dy
                local ok = true
                for ax = -9, 3 do
                    for ay = -2, 2 do
                        if ok and not isStreet(cell:getGridSquare(x + ax, y + ay, 0)) then ok = false end
                    end
                end
                if ok then return x, y end
            end
        end
    end
    return nil
end

------------------------------------------------------------------------
-- hits
------------------------------------------------------------------------

VET.hits = {}

local function addHit(hit)
    hit.t = getTimestampMs()
    VET.hits[#VET.hits + 1] = hit
    VET.log(string.format("    > %s %s(%s) [%d args, from %s]", hit.side, hit.name,
        table.concat(hit.desc, ", "), hit.n, hit.where))
end
VET.onHit = addHit

local function onServerCommand(module, command, args)
    if module ~= "VET" then return end
    if command == "hit" then
        addHit(args)
    elseif command == "acted" then
        VET.R.ack = args
    elseif command == "ready" then
        VET.R.serverReady = args
    end
end

------------------------------------------------------------------------
-- checks
------------------------------------------------------------------------

local function valueMatches(want, got, otherGot, ctx)
    if want == "*" then return true end
    if want == "+" then return tonumber(got) ~= nil and tonumber(otherGot) ~= nil and tonumber(got) > tonumber(otherGot) end
    if want == "-" then return tonumber(got) ~= nil and tonumber(otherGot) ~= nil and tonumber(got) < tonumber(otherGot) end
    if want == "$car" then return got == ctx.carDesc end
    if want == "$trailer" then return got == ctx.trailerDesc end
    if want == "$tower" then return got == ctx.towerDesc end
    if want == "$player" then return got == ctx.playerDesc end
    if string.sub(want, -1) == "*" then return string.sub(got or "", 1, #want - 1) == string.sub(want, 1, -2) end
    return got == want
end

-- nil if the hit's arguments are what the README promises, else why not
local function checkArgs(hit, e, ctx)
    local d = hit.desc
    -- e.on: another vehicle of the test ("trailer", "tower"), default the player's car
    local target = e.on and ctx[e.on .. "Desc"] or ctx.carDesc
    local targetId = e.on and ctx[e.on .. "Id"] or ctx.carId
    local first
    if hit.side == "player" then
        if d[1] ~= ctx.playerDesc then return "arg 1 is " .. tostring(d[1]) .. ", want " .. ctx.playerDesc end
    end
    local function checkPart(got)
        local want = "part:" .. (e.part or "") .. "@" .. tostring(targetId)
        if e.part then
            if got ~= want then return "part is " .. tostring(got) .. ", want " .. want end
        elseif string.sub(got or "", 1, 5) ~= "part:" or not string.find(got, "@" .. tostring(targetId), 1, true) then
            return "part is " .. tostring(got)
        end
        return nil
    end
    if hit.side == "player" then
        local bad = VET.PART_EVENTS[hit.name] and checkPart(d[2])
            or (not VET.PART_EVENTS[hit.name] and d[2] ~= target and ("arg 2 is " .. tostring(d[2]) .. ", want " .. target))
        if bad then return bad end
        first = 3
    else
        if VET.PART_EVENTS[hit.name] then
            if d[1] ~= target then return "arg 1 is " .. tostring(d[1]) .. ", want " .. target end
            local bad = checkPart(d[2])
            if bad then return bad end
            first = 3
        elseif VET.SEAT_EVENTS[hit.name] then
            if d[1] ~= target then return "arg 1 is " .. tostring(d[1]) .. ", want " .. target end
            if d[2] ~= ctx.playerDesc then return "arg 2 is " .. tostring(d[2]) .. ", want " .. ctx.playerDesc end
            first = 3
        else
            if d[1] ~= target then return "arg 1 is " .. tostring(d[1]) .. ", want " .. target end
            first = 2
        end
    end
    if e.values then
        for k, want in ipairs(e.values) do
            local got = d[first + k - 1]
            if not valueMatches(want, got, d[first + (k == 1 and 1 or 0)], ctx) then
                return "value " .. k .. " is " .. tostring(got) .. ", want " .. want
            end
        end
    end
    return nil
end

local function isTestVehicle(desc, ctx)
    return desc == ctx.carDesc or desc == ctx.trailerDesc or desc == ctx.towerDesc
end

-- expectations of a step for this run: one entry per event and side
local function expand(stepDef, ctx)
    local list = {}
    local playerSide = ctx.seated or stepDef.seated == true
    for _, e in ipairs(stepDef.expect or {}) do
        if type(e) == "string" then e = { name = e } end
        local sides = e.sides or VET.EVENTS[e.name]
        if not sides then error("unknown event in step " .. stepDef.id .. ": " .. tostring(e.name)) end
        if string.find(sides, "p", 1, true) and playerSide then
            list[#list + 1] = { e = e, name = e.name, side = "player", want = e.count or 1, got = 0 }
        end
        if string.find(sides, "w", 1, true) then
            list[#list + 1] = { e = e, name = e.name, side = "world", want = e.count or 1, got = 0 }
        end
    end
    return list
end

local function allMet(list)
    for _, x in ipairs(list) do
        if x.got < x.want then return false end
    end
    return true
end

local function isAllowed(stepDef, name)
    for _, allowed in ipairs(stepDef.allow or {}) do
        if allowed == name then return true end
    end
    return false
end

-- a world event on an MP client or a player event on the server is always wrong
local function isWrongSide(hit)
    if not VET.MP then return false end
    if hit.side == "world" and hit.where == "client" then return true end
    if hit.side == "player" and hit.where == "server" then return true end
    return false
end

------------------------------------------------------------------------
-- runner
------------------------------------------------------------------------

VET.R = VET.R or {}
local R = VET.R

local function now() return getTimestampMs() end

local function result(id, status, text)
    R.results[#R.results + 1] = { id = id, status = status, text = text }
    R.counts[status] = (R.counts[status] or 0) + 1
    VET.log(string.format("[%s] %s%s", status, id, text and text ~= "" and (": " .. text) or ""))
end

local function refreshCtx()
    local ctx = R.ctx
    ctx.player = getPlayer()
    ctx.playerDesc = VET.describe(ctx.player)
    ctx.car = ctx.carId and getVehicleById(ctx.carId) or nil
    ctx.carDesc = ctx.carId and ("vehicle:" .. tostring(ctx.carId)) or "vehicle:?"
    ctx.trailer = ctx.trailerId and getVehicleById(ctx.trailerId) or nil
    ctx.trailerDesc = ctx.trailerId and ("vehicle:" .. tostring(ctx.trailerId)) or "vehicle:?"
    ctx.tower = ctx.towerId and getVehicleById(ctx.towerId) or nil
    ctx.towerDesc = ctx.towerId and ("vehicle:" .. tostring(ctx.towerId)) or "vehicle:?"
end

-- run on the car side: here in SP, the server in MP (answer comes back in R.ack)
local function runCarSide(stepId, args)
    args = args or {}
    args.step = stepId
    args.car = R.ctx.carId
    args.trailer = R.ctx.trailerId
    args.tower = R.ctx.towerId
    if VET.MP then
        R.ack = nil
        sendClientCommand(getPlayer(), "VET", "act", args)
        return nil
    end
    local def = VET.STEPS[stepId]
    if not def then
        R.ack = { step = stepId, ok = false, err = "unknown step " .. tostring(stepId) }
        return
    end
    local ok, res = pcall(def.act, R.ctx, args)
    R.ack = { step = stepId, ok = ok, err = not ok and tostring(res) or nil, result = ok and res or nil }
end

local function setListening(on)
    if on then
        VET.listenAll()
        VET.muteDebugPrinters(false)
    else
        VET.unlistenAll()
        VET.muteDebugPrinters(true)
    end
    if VET.MP then sendClientCommand(getPlayer(), "VET", on and "listen" or "unlisten", {}) end
end

local function findLoadedLua(fileName)
    for i = 0, getLoadedLuaCount() - 1 do
        local path = getLoadedLua(i)
        if string.sub(path, -#fileName) == fileName then return path end
    end
    return nil
end

-- the special steps run a small timeline: list of { at = ms, fn = function }
local SPECIAL = {}

SPECIAL.gating = function()
    return {
        { at = 0, fn = function()
            setListening(false)
            local p, w = VE.sideListeners.player, VE.sideListeners.world
            VET.log(string.format("    listeners after removing ours: player %d, world %d", p, w))
            if p ~= 0 or (not VET.MP and w ~= 0) then
                R.stepErrors[#R.stepErrors + 1] = "listeners not at 0 (player " .. p .. ", world " .. w .. ")"
            end
        end },
        { at = 500, fn = function() runCarSide("headlightsOn") end },
        { at = 3500, fn = function() setListening(true) end },
        -- a stale HeadlightsTurnedOn here would be a fail (not expected, strict below)
        { at = 6500, fn = function() runCarSide("headlightsOff") end },
    }
end

SPECIAL.reload = function()
    return {
        { at = 0, fn = function()
            local path = findLoadedLua("VehicleEvents_Player.lua")
            if not path then
                R.stepErrors[#R.stepErrors + 1] = "VehicleEvents_Player.lua not in the loaded list"
            else
                reloadLuaFile(path)
                VET.log("    reloaded " .. path)
            end
            if VET.MP then
                sendClientCommand(getPlayer(), "VET", "reload", {})
            else
                local world = findLoadedLua("VehicleEvents_World.lua")
                if world then
                    reloadLuaFile(world)
                    VET.log("    reloaded " .. world)
                end
            end
        end },
    }
end

SPECIAL.farAway = function()
    return {
        { at = 0, fn = function()
            R.home = { x = math.floor(getPlayer():getX()), y = math.floor(getPlayer():getY()) }
            H.teleport(getPlayer(), R.home.x + 400, R.home.y)
        end },
    }
end

SPECIAL.comeBack = function()
    return {
        { at = 0, fn = function() H.teleport(getPlayer(), R.home.x, R.home.y) end },
    }
end

SPECIAL.death = function()
    return {
        { at = 0, fn = function()
            local player = getPlayer()
            player:setGodMod(false)
            player:setInvulnerable(false)
            player:Kill(nil)
        end },
    }
end

local function startStep(def)
    R.step = def
    R.stepErrors = {}
    R.phase = "quiet"
    R.phaseStart = now()
    VET.log("")
    VET.log("== " .. def.id .. ": " .. def.title)
end

local function evaluate()
    local def = R.step
    local ctx = R.ctx
    local list = R.expected
    local problems, notes, warns = {}, {}, {}
    for _, err in ipairs(R.stepErrors) do problems[#problems + 1] = err end

    local others = 0
    for i = R.hitStart, #VET.hits do
        local hit = VET.hits[i]
        local matched = false
        -- world events of cars that are not part of the test (parked cars around) are not ours
        if hit.side == "world" and not isTestVehicle(hit.desc[1], ctx) then
            matched = true
            others = others + 1
        end
        for _, x in ipairs(list) do
            if not matched and x.name == hit.name and x.side == hit.side then
                matched = true
                local bad = checkArgs(hit, x.e, ctx)
                if bad then
                    problems[#problems + 1] = hit.side .. " " .. hit.name .. ": " .. bad
                else
                    x.got = x.got + 1
                    if x.got > x.want and not def.many then
                        problems[#problems + 1] = hit.side .. " " .. hit.name .. " fired " .. x.got .. " times, want " .. x.want
                    else
                        VET.covered[hit.name .. ":" .. hit.side] = true
                    end
                end
            end
        end
        if not matched then
            local label = hit.side .. " " .. hit.name
            if isWrongSide(hit) then
                problems[#problems + 1] = label .. " fired on the " .. hit.where .. " (wrong side)"
            elseif def.special == "gating" and hit.name == "HeadlightsTurnedOn" then
                problems[#problems + 1] = label .. " fired after the listeners came back (stale value)"
            elseif isAllowed(def, hit.name) then
                notes[#notes + 1] = label
            elseif def.strict then
                problems[#problems + 1] = label .. " fired, not expected"
            else
                warns[#warns + 1] = label
            end
        end
    end
    for _, x in ipairs(list) do
        if x.got < x.want then
            problems[#problems + 1] = x.side .. " " .. x.name .. " missing (" .. x.got .. "/" .. x.want .. ")"
        end
    end

    if #notes > 0 then VET.log("    also fired (allowed): " .. table.concat(notes, ", ")) end
    if others > 0 then VET.log("    ignored " .. others .. " world events of other cars") end
    if #problems > 0 then
        local status = def.tryAuto and "MANUAL" or "FAIL"
        if def.tryAuto then R.autoFailed[#R.autoFailed + 1] = def end
        result(def.id, status, table.concat(problems, "; "))
    elseif #warns > 0 then
        result(def.id, "WARN", "unexpected: " .. table.concat(warns, ", "))
    else
        result(def.id, "PASS", def.title)
    end
end

-- trace = true on a step: the car speed every 250 ms in the log (and the server's in MP)
function VET.traceLine(car, where)
    local driver = car:getDriver()
    return string.format("    speed %s %.2f km/h, gear %s, engine %s, at %.2f,%.2f, driver %s", where,
        car:getCurrentAbsoluteSpeedKmHour(), tostring(car:getTransmissionNumber()), tostring(car:isEngineRunning()),
        car:getX(), car:getY(), driver and VET.describe(driver) or "none")
end

local function traceSpeed(t)
    local def = R.step
    if not def or not def.trace or not R.ctx.car then return end
    if R.phase ~= "act" and R.phase ~= "wait" and R.phase ~= "settle" then return end
    if R.lastTrace and t - R.lastTrace < 250 then return end
    R.lastTrace = t
    VET.log(VET.traceLine(R.ctx.car, "client"))
end

local function startAction()
    local def = R.step
    refreshCtx()
    if def.trace and VET.MP then sendClientCommand(getPlayer(), "VET", "trace", { car = R.ctx.carId }) end
    R.hitStart = #VET.hits + 1
    R.expected = expand(def, R.ctx)
    R.phase = "act"
    R.phaseStart = now()
    R.ack = nil
    R.timeline = nil
    if def.special then
        R.timeline = SPECIAL[def.special]()
        R.timelineIndex = 1
        R.ack = { ok = true }
    elseif def.where == "car" then
        local args = {}
        if def.id == "spawn" then args.x, args.y = R.spawnX, R.spawnY end
        -- a guided step reuses a main step's car side (actStep), the server only knows those
        runCarSide(def.actStep or def.id, args)
    elseif def.where == "manual" then
        -- a manual step may try first (guidedEnter); if that fails the person does it
        if def.act then
            local ok, err = pcall(def.act, R.ctx, {})
            if not ok then VET.log("    automatic try failed (" .. tostring(err) .. "), waiting for a person") end
        end
        R.ack = { ok = true }
    else
        local ok, err = pcall(def.act, R.ctx, {})
        R.ack = { ok = ok, err = not ok and tostring(err) or nil }
    end
end

local function finishStep()
    local def = R.step
    if def.trace and VET.MP then sendClientCommand(getPlayer(), "VET", "trace", {}) end
    if def.seated ~= nil then R.ctx.seated = def.seated end
    R.index = R.index + 1
    R.step = nil
end

local function guidedNote(text)
    local player = getPlayer()
    if not player then return end
    local inCar = player:getVehicle()
    if inCar and R.ctx.car and inCar ~= R.ctx.car then
        -- events of other cars don't count
        player:setHaloNote("TEST: wrong car, get in the police car (" .. R.ctx.carDesc .. ")", 255, 90, 80, 300)
    else
        player:setHaloNote("TEST: " .. text, 255, 220, 80, 300)
    end
end

-- the guided part (a person drives) runs before the last steps, which kill the player
local GUIDED_BEFORE = "enterToDie"

local function buildGuided()
    local list = {}
    -- tries to seat the player; if the car refuses (just reloaded), the note asks the person
    list[#list + 1] = { id = "guidedEnter", title = "Get in the driver seat of the police car", where = "manual",
        seated = true, timeout = 120000,
        act = function(c) H.enter(c.player, c.car, 0) end, expect = { "Entered", "BecameOccupied" } }
    list[#list + 1] = { id = "guidedEngine", title = "Start the engine", where = "car", actStep = "engineOn",
        expect = { "EngineStarted" }, allow = { "EngineStateChanged" } }
    for _, def in ipairs(VET.GUIDED) do
        -- driving fires the same event several times, that's fine here
        list[#list + 1] = { id = def.id, title = def.title, where = "manual", many = true,
            expect = def.expect, allow = def.allow, timeout = 120000 }
    end
    list[#list + 1] = { id = "guidedEngineOff", title = "Engine off", where = "car", actStep = "engineOff", expect = { "EngineStopped" }, allow = { "EngineStateChanged", "HeaterTurnedOff" } }
    list[#list + 1] = { id = "guidedExit", title = "Get out after the guided part", where = "client", seated = false,
        act = function(c) H.exit(c.player, c.car) end, expect = { "Exited", "BecameEmpty" } }
    return list
end

-- the main steps in order, with the guided ones inserted before GUIDED_BEFORE when asked.
-- only-guided: just the car and the guided steps
local function buildOrder()
    local order = {}
    if R.opts.onlyGuided then
        order[1] = VET.STEPS.spawn
        order[2] = VET.STEPS.reset
        for _, g in ipairs(buildGuided()) do order[#order + 1] = g end
        return order
    end
    for _, def in ipairs(VET.STEPS) do
        if R.opts.guided and def.id == GUIDED_BEFORE then
            for _, g in ipairs(buildGuided()) do order[#order + 1] = g end
        end
        order[#order + 1] = def
    end
    return order
end

local function nextStepDef()
    if not R.order then R.order = buildOrder() end
    return R.order[R.index]
end

local function finish()
    R.running = false
    -- coverage: every event and side the README lists (only-guided: the guided events only)
    local only
    if R.opts.onlyGuided then
        only = {}
        for _, def in ipairs(VET.GUIDED) do
            for _, e in ipairs(def.expect) do only[(type(e) == "table" and e.name or e) .. ":player"] = true end
        end
    end
    local missing, manual = {}, {}
    VET.forEachEvent(function(name, side)
        local key = name .. ":" .. side
        if only and not only[key] then return end
        if not VET.covered[key] then
            if VET.MANUAL[key] and not R.opts.guided then
                manual[#manual + 1] = key .. " (" .. VET.MANUAL[key] .. ")"
            else
                missing[#missing + 1] = key
            end
        end
    end)
    table.sort(missing)
    table.sort(manual)
    VET.log("")
    VET.log("== coverage")
    for _, key in ipairs(missing) do result("coverage", "FAIL", key .. " never seen with the right arguments") end
    for _, key in ipairs(manual) do result("coverage", "MANUAL", key) end

    local summary = string.format("VehicleEventsTest %s: %d PASS, %d FAIL, %d WARN, %d MANUAL",
        VET.SIDE, R.counts.PASS or 0, R.counts.FAIL or 0, R.counts.WARN or 0, R.counts.MANUAL or 0)
    VET.log("")
    VET.log(summary)
    local lines = { summary, "" }
    for _, r in ipairs(R.results) do
        if r.status ~= "PASS" then lines[#lines + 1] = r.status .. " " .. r.id .. ": " .. (r.text or "") end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "DONE"
    VET.writeFile("VehicleEventsTest_result.txt", table.concat(lines, "\n") .. "\n")
    if VET.MP then sendClientCommand(getPlayer(), "VET", "done", { summary = summary }) end
    if R.opts.auto then
        R.quitAt = now() + 3000
    end
end

local function checkSetup()
    local problems = VET.checkNames()
    if #problems == 0 then
        result("names", "PASS", "all README event names registered, nothing extra")
    else
        result("names", "FAIL", table.concat(problems, "; "))
    end
    local key = "Sandbox_VehicleEvents_FuelLowPercent"
    local text = getText(key)
    if text == key or string.find(text, "%%%%") then
        result("translation", "FAIL", key .. " shows " .. tostring(text))
    else
        result("translation", "PASS", key .. " = " .. text)
    end
end

-- the game sometimes freezes for a moment (saving, loading chunks): the timers only count
-- the time the game was running, so a freeze can't make a step time out
local FREEZE_MS = 400

local function onTick()
    local tickTime = now()
    if R.lastTick and tickTime - R.lastTick > FREEZE_MS then
        local gap = tickTime - R.lastTick
        if R.phaseStart then R.phaseStart = R.phaseStart + gap end
        if R.quitAt then R.quitAt = R.quitAt + gap end
        if R.running then VET.log(string.format("    (game froze %d ms, timers paused)", gap)) end
    end
    R.lastTick = tickTime
    if R.quitAt and now() >= R.quitAt then
        R.quitAt = nil
        if VET.MP then SendCommandToServer("/quit") end
        getCore():quitToDesktop()
        return
    end
    if not R.running then return end
    local t = now()
    traceSpeed(t)

    if R.phase == "start" then
        if t - R.phaseStart < 3000 then return end
        if VET.MP and not R.serverReady then
            -- a begin sent right at game start can be lost (player not known yet on the server): resend
            if not R.lastBegin or t - R.lastBegin > 3000 then
                R.lastBegin = t
                sendClientCommand(getPlayer(), "VET", "begin", {})
            end
            if t - R.phaseStart > 60000 then
                result("server", "FAIL", "server never answered, is VehicleEventsTest in its Mods=?")
                finish()
            end
            return
        end
        if VET.MP then
            VET.log("server ready, " .. tostring(R.serverReady.added) .. " listeners")
            if R.serverReady.problems and R.serverReady.problems ~= "" then
                result("names server", "FAIL", R.serverReady.problems)
            end
        end
        R.spawnX, R.spawnY = H.findStreet(getPlayer())
        -- a new world puts the player anywhere: go to a known street in Muldraugh (default map)
        -- and look again once the chunks there are loaded
        if not R.spawnX and (R.streetTries or 0) < 10 then
            R.streetTries = (R.streetTries or 0) + 1
            if R.streetTries == 1 then
                VET.log("no street near the player, going to Muldraugh")
                H.teleport(getPlayer(), 10720, 10195)
            end
            R.phaseStart = t
            return
        end
        if not R.spawnX then
            result("street", "FAIL", "no street within 70 tiles of the player")
            finish()
            return
        end
        VET.log(string.format("street at %d,%d", R.spawnX, R.spawnY))
        R.phase = "next"
        return
    end

    if R.phase == "next" then
        local def = nextStepDef()
        if not def then
            finish()
            return
        end
        startStep(def)
        return
    end

    local def = R.step
    if R.phase == "quiet" then
        local last = VET.hits[#VET.hits]
        local quietFor = last and (t - last.t) or QUIET_MS
        if (quietFor >= QUIET_MS and t - R.phaseStart >= 300) or t - R.phaseStart > QUIET_MAX_MS then
            if def.where == "manual" then
                VET.log("    waiting for a person: " .. def.title)
            end
            -- the car must exist here (after a chunk unload it comes back as a new object)
            refreshCtx()
            if not R.ctx.car and def.id ~= "spawn" and def.special ~= "comeBack" and def.special ~= "farAway" then
                result(def.id, "FAIL", "test car " .. tostring(R.ctx.carId) .. " not found")
                finishStep()
                R.phase = "next"
                return
            end
            startAction()
        end
        return
    end

    if R.phase == "act" then
        if R.timeline then
            local item = R.timeline[R.timelineIndex]
            while item and t - R.phaseStart >= item.at do
                local ok, err = pcall(item.fn)
                if not ok then R.stepErrors[#R.stepErrors + 1] = "timeline error: " .. tostring(err) end
                R.timelineIndex = R.timelineIndex + 1
                item = R.timeline[R.timelineIndex]
            end
            if item then return end
        end
        if def.where == "manual" then guidedNote(def.title) end
        if R.ack then
            -- in MP the server loads the chunks around a new player a bit later: try the spawn again
            local notLoaded = R.ack.ok and R.ack.result and R.ack.result.notLoaded
            if notLoaded then
                R.ack.ok = false
                R.ack.err = notLoaded
            end
            if not R.ack.ok then
                if notLoaded and t - R.phaseStart < 30000 then
                    if not R.retryAt then
                        R.retryAt = t + 2000
                        VET.log("    " .. tostring(R.ack.err) .. ", trying again")
                    elseif t >= R.retryAt then
                        R.retryAt = nil
                        runCarSide(def.id, { x = R.spawnX, y = R.spawnY })
                    end
                    return
                end
                R.retryAt = nil
                result(def.id, "FAIL", "action error: " .. tostring(R.ack.err))
                -- no car, no test: stop here instead of failing every step after
                if def.setup then
                    finish()
                    return
                end
                finishStep()
                R.phase = "next"
                return
            end
            if R.ack.result then
                if R.ack.result.car then R.ctx.carId = R.ack.result.car end
                if R.ack.result.trailer then R.ctx.trailerId = R.ack.result.trailer end
                if R.ack.result.tower then R.ctx.towerId = R.ack.result.tower end
                refreshCtx()
            end
            R.phase = "wait"
            R.phaseStart = t
        elseif t - R.phaseStart > ACK_MS then
            result(def.id, "FAIL", "no answer from the server")
            finishStep()
            R.phase = "next"
        end
        return
    end

    if R.phase == "wait" then
        refreshCtx()
        if def.hold and R.ctx.car then pcall(def.hold, R.ctx) end
        if def.where == "manual" then guidedNote(def.title) end
        -- the car came back after the far away step
        local done
        if def.special == "comeBack" then
            done = R.ctx.car ~= nil and t - R.phaseStart > 5000
        elseif def.setup then
            done = R.ctx.car ~= nil
        else
            local list = R.expected
            for _, x in ipairs(list) do x.got = 0 end
            for i = R.hitStart, #VET.hits do
                local hit = VET.hits[i]
                if hit.side == "player" or isTestVehicle(hit.desc[1], R.ctx) then
                    for _, x in ipairs(list) do
                        if x.name == hit.name and x.side == hit.side then x.got = x.got + 1 end
                    end
                end
            end
            done = #list > 0 and allMet(list)
            for _, x in ipairs(list) do x.got = 0 end
        end
        if done or t - R.phaseStart > (def.timeout or TIMEOUT_MS) then
            R.phase = "settle"
            R.phaseStart = t
        end
        return
    end

    if R.phase == "settle" then
        if t - R.phaseStart < SETTLE_MS then return end
        if def.setup then
            if R.ctx.car then
                result(def.id, "PASS", def.title .. " (car " .. tostring(R.ctx.carId) .. ")")
            else
                result(def.id, "FAIL", def.title .. ": car not found")
            end
        else
            evaluate()
        end
        finishStep()
        R.phase = "next"
    end
end

-- in -debug a Lua error opens the Lua debugger, which stops the whole game until someone
-- closes it. Errors still go to console.txt, run.sh reads them from there
local function noDebuggerPopup()
    if UIManager and UIManager.setShowLuaDebuggerOnError then
        UIManager.setShowLuaDebuggerOnError(false)
    end
end

function VET.start(opts)
    opts = opts or {}
    noDebuggerPopup()
    VET.resetLog()
    VET.log("VehicleEventsTest " .. VET.SIDE .. (opts.onlyGuided and " (only guided)" or opts.guided and " (guided)" or "")
        .. (opts.auto and " (auto)" or ""))
    VET.hits = {}
    VET.covered = {}
    VET.active = true
    local added = VET.listenAll()
    VET.log("listening to " .. added .. " events here")
    R.opts = opts
    R.results = {}
    R.counts = {}
    R.autoFailed = {}
    R.ctx = { seated = false }
    R.index = 1
    R.order = nil
    R.running = true
    R.phase = "start"
    R.phaseStart = now()
    R.serverReady = nil

    -- fast world checks for the test, read live by the API
    if not isClient() then
        SandboxVars.VehicleEvents = SandboxVars.VehicleEvents or {}
        SandboxVars.VehicleEvents.WorldCheckMs = 100
    end
    local player = getPlayer()
    player:setGodMod(true)
    player:setInvisible(true)
    player:setGhostMode(true)
    if isClient() then
        sendClientCommand(player, "VET", "begin", {})
    end
    checkSetup()
end

------------------------------------------------------------------------
-- automation: run.sh writes VehicleEventsTest_auto.txt, "sp [guided]" or "mp user pass port [guided]"
------------------------------------------------------------------------

local AUTO_FILE = "VehicleEventsTest_auto.txt"
local MODE_FILE = "VehicleEventsTest_mode.txt"

local function split(line)
    local words = {}
    for word in string.gmatch(line, "%S+") do words[#words + 1] = word end
    return words
end

local menu = { ticks = 0 }

-- first MP connect (run.sh wipes the world each time): no character yet, take the first spawn
-- town and the default character
local function onFETickSkipCreation()
    local screen = MainScreen.instance
    if not screen then return end
    if screen.mapSpawnSelect and screen.mapSpawnSelect:getIsVisible() then
        screen.mapSpawnSelect:onOptionMouseDown({ internal = "NEXT" }, 0, 0)
    elseif screen.charCreationProfession and screen.charCreationProfession:getIsVisible() then
        screen.charCreationProfession:onOptionMouseDown({ internal = "NEXT" }, 0, 0)
    elseif screen.charCreationMain and screen.charCreationMain:getIsVisible() then
        screen.charCreationMain:onOptionMouseDown({ internal = "NEXT" }, 0, 0)
    end
end

local function onFETickMenu()
    menu.ticks = menu.ticks + 1
    if menu.ticks < 30 then return end
    Events.OnFETick.Remove(onFETickMenu)
    local words = split(menu.line)
    if words[1] == "sp" then
        print("[VET] auto: new single player world")
        SandboxVars.Zombies = 6
        getWorld():setGameMode("Sandbox")
        getWorld():setMap("Muldraugh, KY")
        createWorld("VehicleEventsTest_" .. tostring(getTimestampMs()))
        GameWindow.doRenderEvent(false)
        forceChangeState(LoadingQueueState.new())
    elseif words[1] == "mp" then
        print("[VET] auto: connecting as " .. tostring(words[2]))
        Events.OnFETick.Add(onFETickSkipCreation)
        serverConnect(words[2], words[3], "127.0.0.1", "", words[4], "", "", false, true, 1, "")
    end
end

local function onMainMenuEnter()
    local line = VET.readLine(AUTO_FILE)
    if not line then return end
    noDebuggerPopup()
    -- used once: a crash back to the menu does not start it again
    VET.writeFile(AUTO_FILE, "")
    VET.writeFile(MODE_FILE, line)
    menu.line = line
    menu.ticks = 0
    Events.OnFETick.Add(onFETickMenu)
end

local function onGameStart()
    local line = VET.readLine(MODE_FILE)
    if not line then return end
    VET.writeFile(MODE_FILE, "")
    local guided = string.find(line, "guided", 1, true) ~= nil
    local onlyGuided = string.find(line, "only-guided", 1, true) ~= nil
    VET.start({ auto = true, guided = guided, onlyGuided = onlyGuided })
end

if VET.onTick then Events.OnTick.Remove(VET.onTick) end
VET.onTick = onTick
Events.OnTick.Add(onTick)

if VET.onServerCommand then Events.OnServerCommand.Remove(VET.onServerCommand) end
VET.onServerCommand = onServerCommand
Events.OnServerCommand.Add(onServerCommand)

Events.OnMainMenuEnter.Add(onMainMenuEnter)

-- joining a server reloads the Lua (server mod list), which drops the handler added in
-- onFETickMenu: add it again on load while an MP test run is going (run.sh clears the mode file)
local mode = VET.readLine(MODE_FILE)
if mode and string.sub(mode, 1, 2) == "mp" then
    Events.OnFETick.Remove(onFETickSkipCreation)
    Events.OnFETick.Add(onFETickSkipCreation)
end
Events.OnGameStart.Add(onGameStart)
