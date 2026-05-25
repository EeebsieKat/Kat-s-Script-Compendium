local M = {}

local beltTasks = {}
local beltPart = nil
local activeSlots = {}
local lastSlotData = {}  -- cache to detect changes

function M.init(belt, config)
    beltPart = belt
    config = config or {}
    activeSlots = config.slots or {0, 1, 2, 3, 4, 5, 6, 7, 8}

    for i, slot in ipairs(activeSlots) do
        local partName = "belt_slot_" .. slot
        local taskName = "belt_item_" .. slot
        beltTasks[slot] = belt[partName]:newItem(taskName)
            :setDisplayMode("FIXED")
            :setScale(0.1, 0.1, 0.1)
        lastSlotData[slot] = ""  -- init cache as empty
    end
end

-- Ping: receives a single slot update on all clients
local function syncSlot(slot, itemId)
    if beltTasks[slot] then
        beltTasks[slot]:setItem(itemId or "minecraft:air")
    end
end

pings.syncBeltSlot = syncSlot

local tickTimer = 0

function events.tick()
    if not player:isLoaded() or beltPart == nil then return end
    if not host then return end

    tickTimer = tickTimer + 1
    if tickTimer < 5 then return end
    tickTimer = 0

    local nbt = player:getNbt()
    local inventory = nbt and nbt.Inventory
    if not inventory then return end

    -- Build current state
    local currentSlotData = {}
    for _, activeSlot in ipairs(activeSlots) do
        currentSlotData[activeSlot] = "minecraft:air"  -- default
    end
    for _, itemData in pairs(inventory) do
        local slot = itemData.Slot
        if currentSlotData[slot] ~= nil then
            currentSlotData[slot] = itemData.id
        end
    end

    -- Only ping slots that actually changed
    for slot, itemId in pairs(currentSlotData) do
        if lastSlotData[slot] ~= itemId then
            lastSlotData[slot] = itemId
            pings.syncBeltSlot(slot, itemId)
        end
    end
end

return M