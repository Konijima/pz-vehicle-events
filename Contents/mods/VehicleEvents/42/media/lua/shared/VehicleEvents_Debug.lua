-- debug mode only (-debug): prints every VehicleEvents event so u can see them fire
require "VehicleEvents"

if not getDebug() then return end

local VE = VehicleEvents

local function describe(value)
    if instanceof(value, "BaseVehicle") then return "vehicle " .. tostring(value:getId()) end
    if instanceof(value, "IsoPlayer") then return "player " .. tostring(value:getUsername()) end
    if instanceof(value, "VehiclePart") then return "part " .. tostring(value:getId()) end
    if instanceof(value, "InventoryItem") then return "item " .. tostring(value:getFullType()) end
    return tostring(value)
end

local function makePrinter(eventName)
    local function printEvent(...)
        local args = { ... }
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = describe(args[i])
        end
        print("[VehicleEvents] " .. eventName .. " " .. table.concat(parts, ", "))
    end
    return printEvent
end

-- event name -> printer, kept so a reload removes the old ones first
VE.debugPrinters = VE.debugPrinters or {}

local function hookAll(events)
    if not events then return end
    for _, eventName in pairs(events) do
        local old = VE.debugPrinters[eventName]
        if old then Events[eventName].Remove(old) end
        local printer = makePrinter(eventName)
        Events[eventName].Add(printer)
        VE.debugPrinters[eventName] = printer
    end
end

for i = 1, #VE.watcherList do
    hookAll(VE.watcherList[i].playerEvents)
    hookAll(VE.watcherList[i].worldEvents)
end
for i = 1, #VE.partWatcherList do
    hookAll(VE.partWatcherList[i].playerEvents)
    hookAll(VE.partWatcherList[i].worldEvents)
end
hookAll(VE.seatEvents.player)
hookAll(VE.seatEvents.world)
hookAll(VE.loadEvents)
