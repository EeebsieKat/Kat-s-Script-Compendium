local M = {}

local beltTasks = {}
local beltPart = nil

function M.init(belt)
    beltPart = belt
    for i = 1, 9 do
        beltTasks[i] = belt["belt_slot_" .. i]:newItem("belt_item_" .. i)
            :setDisplayMode("FIXED")
            :setScale(0.1, 0.1, 0.1)
    end
end

local function syncHotbar(slotData)
    -- slotData is a table: { [slotIndex(1-9)] = "mod_id:item_id" }
    for i = 1, 9 do
        if beltTasks[i] then
            beltTasks[i]:setItem(slotData[i] or "minecraft:air")
        end
    end
end

pings.syncBeltHotbar = syncHotbar

local tickTimer = 0

function events.tick()
    if not player:isLoaded() or beltPart == nil then return end
    if not host then return end

    tickTimer = tickTimer + 1
    if tickTimer < 5 then return end
    tickTimer = 0

    local nbt = player:getNbt()
    local inventory = nbt and nbt.Inventory

    local slotData = {}

    if inventory then
        for _, itemData in pairs(inventory) do
            local slot = itemData.Slot
            if slot >= 0 and slot <= 8 then
                slotData[slot + 1] = itemData.id
            end
        end
    end

    pings.syncBeltHotbar(slotData)
end

return M