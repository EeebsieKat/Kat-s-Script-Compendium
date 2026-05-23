local M = {}

local beltTasks = {}
local beltPart = nil
local activeSlots = {}

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
    end
end

-- Ping: receives hotbar data on all clients
local function syncHotbar(slotData)
    for slot, _ in pairs(beltTasks) do
        beltTasks[slot]:setItem(slotData[slot] or "minecraft:air")
    end
end

pings.syncBeltHotbar = syncHotbar

local tickTimer = 0

function events.tick()
    if not player:isLoaded() or beltPart == nil then return end
    if not host:isHost() then return end

    tickTimer = tickTimer + 1
    if tickTimer < 5 then return end
    tickTimer = 0

    local nbt = player:getNbt()
    local inventory = nbt and nbt.Inventory

    local slotData = {}

    if inventory then
        for _, itemData in pairs(inventory) do
            local slot = itemData.Slot
            -- only sync slots you care about
            for _, activeSlot in ipairs(activeSlots) do
                if slot == activeSlot then
                    slotData[slot] = itemData.id
                    break
                end
            end
        end
    end

    pings.syncBeltHotbar(slotData)
end

return M